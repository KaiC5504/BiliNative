import AVFoundation
import Foundation
import Network
import Observation
import UIKit
import BiliShared
import BiliAPI
import Ripper
import LocalHTTP
import DevLog

protocol PlayURLProvider: Sendable {
    func playURL(quality: Int) async throws -> PlayURLInfo
}

struct BiliPlayURLProvider: PlayURLProvider {
    let client: BiliClient
    let bvid: String
    let cid: Int64

    func playURL(quality: Int) async throws -> PlayURLInfo {
        try await client.ensureRiskCookies()
        return try await client.playURL(bvid: bvid, cid: cid, quality: quality)
    }
}

struct PlaybackEnvironment {
    let provider: PlayURLProvider
    let router: PlaybackRouter
    let server: LocalServer
    let directLoader: DirectPlaylistLoader
    let transport: RangeTransport
    let auto: AutoConcurrency
    let nodeMode: NodeMode
    let policy: MediaURLPolicy
    let ripperConfig: RipperConfig
    let codecMemory: CodecMemory
    let mediaHeaders: [String: String]
}

extension Notification.Name {
    /// Posted with the server as object when the local server's listener stops.
    static let localServerStopped = Notification.Name("bilinative.localServerStopped")
}

enum PlaybackFailure: Error, Equatable {
    /// Every codec left is one this phone's codec memory refuses.
    case noPlayableCodec
    /// Every codec failed in this playback, without a verdict worth remembering.
    case unplayable
    case network

    var userMessage: String {
        switch self {
        case .noPlayableCodec: return "本机无法播放这个视频的任何编码，可在设置里重置编码记忆后重试"
        case .unplayable: return "这个视频暂时无法在本机播放，请稍后重试"
        case .network: return "网络连接中断，请检查网络后重试"
        }
    }
}

@MainActor
@Observable
final class PlaybackController {
    enum Mode: Equatable {
        case ripper, direct, directFallback

        var label: String {
            switch self {
            case .ripper: return "BTR"
            case .direct: return "直连"
            case .directFallback: return "直连（回退）"
            }
        }
    }

    enum Phase: Equatable {
        case idle, loading, playing
        case failed(String)
    }

    enum ItemFailure: Equatable {
        case format, network, unknown
    }

    struct ErrorLogEntry: Sendable {
        let domain: String
        let status: Int
        let comment: String
    }

    private struct PathSignature: Equatable, Sendable {
        let up: Bool
        let interfaces: [String]
        let gateways: [String]
    }

    /// Direct preparation tries each address for a few seconds; this caps the whole of it.
    private static let directPrepareSeconds = 20.0
    /// A network failure in direct mode restarts with fresh URLs at most this often.
    private static let networkRestartSeconds = 60.0

    let player = AVPlayer()
    private(set) var mode: Mode = .ripper
    private(set) var phase: Phase = .idle
    private(set) var qualities: [QualityOption] = []
    private(set) var selectedQuality: Int
    /// The quality of the stream actually chosen; selectedQuality is only the ceiling asked for.
    private(set) var playingQuality: Int?
    private(set) var codec: VideoCodec
    private(set) var btrEnabled: Bool
    private(set) var overlay = OverlayStats()

    @ObservationIgnored private let environment: PlaybackEnvironment
    @ObservationIgnored private var session: RipperSession?
    @ObservationIgnored private var routerToken: String?
    @ObservationIgnored private var directToken: String?
    @ObservationIgnored private var choice: TrackChoice?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var work: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var workCount = 0
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var seekStartedAt: Date?
    @ObservationIgnored private var refreshedAfterFatal = false
    @ObservationIgnored private var refreshingAfterFatal = false
    @ObservationIgnored private var lastDelivered: Int64?
    /// Bumped by every stop, restart, switch and failure; async work and callbacks of an older epoch do nothing.
    @ObservationIgnored private var epoch = 0
    /// Codec kinds that failed in this playback only: not AVFoundation's verdict on the phone, or hev1 in direct mode.
    @ObservationIgnored private var rejectedHere: Set<String> = []
    /// Codec kinds whose unexplained failure already got one retry with fresh URLs.
    @ObservationIgnored private var unknownRetried: Set<String> = []
    @ObservationIgnored private var lastNetworkRestart: Date?
    /// Set once this playback left BTR mode; later restarts stay direct.
    @ObservationIgnored private var forcedDirect = false
    /// The position to report while no item is loaded, so a retry resumes where playback stopped.
    @ObservationIgnored private var heldPosition = 0.0

    init(environment: PlaybackEnvironment, quality: Int, codec: VideoCodec, btrEnabled: Bool) {
        self.environment = environment
        selectedQuality = quality
        self.codec = codec
        self.btrEnabled = btrEnabled
        player.automaticallyWaitsToMinimizeStalling = true
    }

    var currentSeconds: Double {
        guard player.currentItem != nil else { return heldPosition }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    // MARK: public actions

    func start(at time: Double = 0) async {
        rejectedHere = []
        unknownRetried = []
        lastNetworkRestart = nil
        forcedDirect = false
        startedAt = Date()
        overlay = OverlayStats()
        watchNetwork()
        await launch { await $0.begin(at: time) }
    }

    func setBTR(_ enabled: Bool) async {
        Logger.shared.info(.ui, "btr switch", ["on": .init(enabled)])
        btrEnabled = enabled
        await restart()
    }

    func setQuality(_ quality: Int) async {
        Logger.shared.info(.ui, "quality", ["id": .init(quality)])
        selectedQuality = quality
        await restart()
    }

    func setCodec(_ codec: VideoCodec) async {
        Logger.shared.info(.ui, "codec", ["codec": .init(codec.rawValue)])
        self.codec = codec
        await restart()
    }

    func stop() {
        heldPosition = currentSeconds
        advance()
        teardownPlayback()
        pathMonitor?.cancel()
        pathMonitor = nil
        phase = .idle
    }

    #if DEBUG
    func debugKillServer() {
        environment.server.stop()
        let current = epoch
        Task { await launch { await $0.serverStopped(epoch: current) } }
    }
    #endif

    // MARK: modes

    private func begin(at time: Double) async {
        let current = advance()
        refreshTask?.cancel()
        phase = .loading
        heldPosition = time
        refreshedAfterFatal = false
        refreshingAfterFatal = false
        do {
            let info = try await environment.provider.playURL(quality: selectedQuality)
            try ensureCurrent(current)
            qualities = info.qualityOptions
            guard let dash = info.dash else { throw BiliError.notDash }
            let ripper = try await ripperAvailable(epoch: current)
            let choice = try pickTracks(dash, skipHEV1: !ripper)
            self.choice = choice
            playingQuality = choice.video.id
            Logger.shared.info(.player, "choice", ["quality": .init(choice.video.id), "codecs": .init(choice.video.codecs),
                                                   "audio": .init(choice.audio.id), "node": .init(NodeCatalog.nodeKey(of: choice.video.baseURL)),
                                                   "btr": .init(ripper)])
            if ripper {
                try await startRipper(choice, at: time, epoch: current)
            } else {
                try await startDirect(choice, at: time, fallback: btrEnabled, epoch: current)
            }
            if mode == .ripper { scheduleRefresh(for: choice, epoch: current) }
        } catch {
            await handle(error, at: time, epoch: current)
        }
    }

    /// iOS reclaims a suspended app's listening socket, so a stopped server is started again before
    /// a BTR playback settles for direct mode.
    private func ripperAvailable(epoch current: Int) async throws -> Bool {
        guard btrEnabled, !forcedDirect else { return false }
        let server = environment.server
        if !server.isRunning {
            Logger.shared.warn(.server, "not running at playback start, restarting", ["state": .init(String(describing: server.state))])
            do {
                try await server.start()
                Logger.shared.info(.server, "restarted")
            } catch {
                Logger.shared.error(.server, "restart failed; playing direct", ["error": .init(String(describing: error))])
            }
            try ensureCurrent(current)
        }
        return server.isRunning
    }

    private func pickTracks(_ dash: Dash, skipHEV1: Bool) throws -> TrackChoice {
        let memory = environment.codecMemory
        let excluded = memory.failedKinds.union(rejectedHere)
        if let choice = Self.choose(dash, quality: selectedQuality, codecOrder: memory.order(preferred: codec), excluded: excluded,
                                    skipHEV1: skipHEV1) {
            return choice
        }
        let offered = TrackSelector.choose(dash, quality: selectedQuality, codecOrder: []) != nil
        let withoutMemory = Self.choose(dash, quality: selectedQuality, codecOrder: VideoCodec.allCases, excluded: rejectedHere,
                                        skipHEV1: skipHEV1) != nil
        Logger.shared.warn(.player, "no track", ["excluded": .init(excluded.sorted().joined(separator: ",")), "offered": .init(offered),
                                                 "skipHEV1": .init(skipHEV1), "memoryDecided": .init(withoutMemory)])
        guard offered else { throw PlaybackError.noTrack }
        throw withoutMemory ? PlaybackFailure.noPlayableCodec : PlaybackFailure.unplayable
    }

    /// TrackSelector falls back to any codec the quality has, so rejected kinds are removed from the
    /// streams first. Once anything was rejected, codecs of unknown kind are left out too. Direct mode
    /// cannot rename hev1 to hvc1, and AVPlayer refuses hev1, so those streams can be skipped up front.
    nonisolated static func choose(_ dash: Dash, quality: Int, codecOrder: [VideoCodec], excluded: Set<String>,
                                   skipHEV1: Bool = false) -> TrackChoice? {
        var banned = excluded
        if !banned.isEmpty { banned.insert("other") }
        let videos = dash.video.filter { !banned.contains(TrackSelector.codecKind($0)) && !(skipHEV1 && isHEV1($0)) }
        guard !videos.isEmpty else { return nil }
        return TrackSelector.choose(Dash(duration: dash.duration, video: videos, audio: dash.audio), quality: quality,
                                    codecOrder: codecOrder.filter { !banned.contains($0.rawValue) })
    }

    nonisolated private static func isHEV1(_ stream: DashStream) -> Bool {
        stream.codecs.hasPrefix("hev1")
    }

    private enum Reroute: Error {
        /// BTR mode failed on a hev1 stream, which direct mode cannot play: choose again for direct mode.
        case directWithoutHEV1
    }

    private func startRipper(_ choice: TrackChoice, at time: Double, epoch current: Int) async throws {
        let session = RipperSession(sources: [.video: (choice.video.baseURL, choice.video.backupURLs),
                                              .audio: (choice.audio.baseURL, choice.audio.backupURLs)],
                                    mode: environment.nodeMode, config: environment.ripperConfig, transport: environment.transport,
                                    auto: environment.auto, policy: environment.policy)
        session.onFatal = { [weak self, weak session] error in
            Task { @MainActor in await self?.launch { await $0.ripperFailed(error, from: session, epoch: current) } }
        }
        do {
            let prepared = try await PlaybackBuilder.prepare(choice: choice) { kind, stream in
                let headers = try await session.loadHeaders(kind, through: stream.indexRange.end)
                return (headers.bytes, headers.totalSize)
            }
            try ensureCurrent(current)
            session.setSegments(.video, prepared.video.segments)
            session.setSegments(.audio, prepared.audio.segments)
            let token = environment.router.register(PlaybackBuilder.ripperAssets(prepared, session: session))
            guard let url = environment.server.url(token: token, name: "master.m3u8") else {
                environment.router.unregister(token)
                throw PlaybackError.serverDown
            }
            teardownSession()
            self.session = session
            routerToken = token
            mode = .ripper
            try await load(url: url, viaLoader: false, at: time, epoch: current)
        } catch {
            session.close()
            if error is CancellationError || current != epoch { throw error }
            if case .codecUnplayable? = error as? PlaybackError { throw error }
            Logger.shared.warn(.player, "btr start failed, going direct", ["error": .init(String(describing: error))])
            forcedDirect = true
            if Self.isHEV1(choice.video) { throw Reroute.directWithoutHEV1 }
            try await startDirect(choice, at: time, fallback: true, epoch: current)
        }
    }

    private func startDirect(_ choice: TrackChoice, at time: Double, fallback: Bool, epoch current: Int) async throws {
        let transport = environment.transport
        let prepared: PreparedPlayback
        do {
            prepared = try await PlaybackBuilder.within(Self.directPrepareSeconds) {
                try await PlaybackBuilder.prepareDirect(choice: choice, transport: transport)
            }
        } catch is PlaybackBuilder.CandidateTimeout {
            Logger.shared.error(.player, "direct headers timed out", ["seconds": .init(Self.directPrepareSeconds)])
            throw PlaybackError.noSource
        }
        try ensureCurrent(current)
        teardownSession()
        if let directToken { environment.directLoader.unregister(directToken) }
        let token = PlaybackRouter.makeToken()
        directToken = token
        let url = environment.directLoader.register(token: token, playlists: PlaybackBuilder.directPlaylists(prepared, token: token))
        mode = fallback ? .directFallback : .direct
        try await load(url: url, viaLoader: true, at: time, epoch: current)
    }

    private func load(url: URL, viaLoader: Bool, at time: Double, epoch current: Int) async throws {
        detachObservers()
        var options: [String: Any] = [:]
        if viaLoader {
            // The CDN can refuse requests without the transport's Referer and User-Agent. AVURLAssetHTTPHeaderFieldsKey
            // is not in the public headers; AVFoundation honours it for the CDN requests of direct mode.
            options["AVURLAssetHTTPHeaderFieldsKey"] = environment.mediaHeaders
            if let agent = environment.mediaHeaders["User-Agent"] { options[AVURLAssetHTTPUserAgentKey] = agent }
        }
        let asset = AVURLAsset(url: url, options: options)
        if viaLoader { asset.resourceLoader.setDelegate(environment.directLoader, queue: environment.directLoader.queue) }
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        attachObservers(item, epoch: current)
        player.replaceCurrentItem(with: item)
        if time > 0 {
            _ = await player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            try ensureCurrent(current)
        }
        player.play()
        startStatsLoop()
        Logger.shared.info(.player, "load", ["mode": .init(mode.label), "at": .init(time)])
    }

    // MARK: failures

    private func ripperFailed(_ error: Error, from failing: RipperSession?, epoch current: Int) async {
        guard current == epoch, let failing, failing === session, let choice else { return }
        // A pipelined request that failed before the refresh landed says nothing about the new URLs.
        if refreshingAfterFatal {
            Logger.shared.info(.player, "btr range failed during url refresh, ignored", ["error": .init(String(describing: error))])
            return
        }
        if !refreshedAfterFatal {
            refreshedAfterFatal = true
            refreshingAfterFatal = true
            Logger.shared.warn(.player, "btr range failed, refreshing urls", ["error": .init(String(describing: error))])
            await refreshURLs(for: choice, epoch: current)
            if current == epoch { refreshingAfterFatal = false }
            return
        }
        await fallBackToDirect(reason: "btr failed again", epoch: current)
    }

    private func serverStopped(epoch current: Int) async {
        guard current == epoch, mode == .ripper else { return }
        await fallBackToDirect(reason: "local server stopped", epoch: current)
    }

    private func fallBackToDirect(reason: String, epoch current: Int) async {
        guard current == epoch, let choice else { return }
        let next = advance()
        refreshTask?.cancel()
        forcedDirect = true
        phase = .loading
        let time = currentSeconds
        Logger.shared.warn(.player, "fallback to direct", ["reason": .init(reason), "at": .init(time)])
        if Self.isHEV1(choice.video) {
            await begin(at: time)
            return
        }
        do {
            try await startDirect(choice, at: time, fallback: true, epoch: next)
        } catch {
            await handle(error, at: time, epoch: next)
        }
    }

    private func itemFailed(_ failure: ItemFailure, detail: String, epoch current: Int) async {
        guard current == epoch, let choice else { return }
        Logger.shared.error(.player, "item failed", ["mode": .init(mode.label), "kind": .init(String(describing: failure)),
                                                     "error": .init(detail)])
        if mode == .ripper {
            await fallBackToDirect(reason: "item failed in btr mode", epoch: current)
            return
        }
        let time = currentSeconds
        let kind = TrackSelector.codecKind(choice.video)
        switch failure {
        case .network:
            guard claimNetworkRestart() else { return fail(PlaybackFailure.network) }
            Logger.shared.warn(.player, "restarting with fresh urls", ["at": .init(time)])
            await begin(at: time)
        case .unknown:
            // Unexplained failures are often expired URLs: one fresh start before the codec is blamed.
            if !unknownRetried.contains(kind), claimNetworkRestart() {
                unknownRetried.insert(kind)
                Logger.shared.warn(.player, "unexplained failure, restarting with fresh urls", ["at": .init(time), "kind": .init(kind)])
                await begin(at: time)
            } else {
                await nextCodec(rejecting: kind, remember: false, at: time)
            }
        case .format:
            // Direct mode serves hev1 unpatched, so its refusal says nothing about what this phone can decode.
            await nextCodec(rejecting: kind, remember: !Self.isHEV1(choice.video), at: time)
        }
    }

    private func claimNetworkRestart() -> Bool {
        if let last = lastNetworkRestart, Date().timeIntervalSince(last) < Self.networkRestartSeconds { return false }
        lastNetworkRestart = Date()
        return true
    }

    private func nextCodec(rejecting kind: String, remember: Bool, at time: Double) async {
        if remember {
            environment.codecMemory.markFailed(kind)
        } else {
            rejectedHere.insert(kind)
        }
        Logger.shared.warn(.player, "codec failed", ["kind": .init(kind), "remembered": .init(remember)])
        await begin(at: time)
    }

    private func handle(_ error: Error, at time: Double, epoch current: Int) async {
        guard current == epoch, !(error is CancellationError), !Task.isCancelled else { return }
        if error is Reroute {
            await begin(at: time)
            return
        }
        if case .codecUnplayable(let reason)? = error as? PlaybackError, let choice {
            Logger.shared.warn(.player, "codec unplayable", ["reason": .init(reason)])
            await nextCodec(rejecting: TrackSelector.codecKind(choice.video), remember: false, at: time)
            return
        }
        fail(error)
    }

    private func fail(_ error: Error) {
        heldPosition = currentSeconds
        advance()
        teardownPlayback()
        phase = .failed(Self.userMessage(error))
        Logger.shared.error(.player, "failed", ["error": .init(String(describing: error))])
    }

    private static func userMessage(_ error: Error) -> String {
        if let error = error as? BiliError { return error.userMessage }
        if let error = error as? PlaybackError { return error.userMessage }
        if let error = error as? PlaybackFailure { return error.userMessage }
        if error is URLError { return "网络连接失败，请检查网络后重试" }
        return "播放失败，请稍后重试"
    }

    /// Format means AVFoundation could not parse or decode the media. Any sign of a network or HTTP
    /// failure wins: an expired URL's 403 body also fails to parse.
    nonisolated static func classify(_ error: Error?, log: [ErrorLogEntry]) -> ItemFailure {
        var chain: [NSError] = []
        var next = error.map { $0 as NSError }
        while let current = next, chain.count < 8 {
            chain.append(current)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let networkInLog = log.contains { entry in
            entry.domain == NSURLErrorDomain || (400..<600).contains(entry.status) || entry.comment.hasPrefix("HTTP ")
        }
        if networkInLog || chain.contains(where: { $0.domain == NSURLErrorDomain }) { return .network }
        let formatCodes: Set<AVError.Code> = [.decodeFailed, .decoderNotFound, .fileFormatNotRecognized, .failedToParse]
        let format = chain.contains { error in
            error.domain == AVFoundationErrorDomain && AVError.Code(rawValue: error.code).map { formatCodes.contains($0) } == true
        }
        return format ? .format : .unknown
    }

    /// Only entries from around the failure: an earlier 403 the player recovered from says nothing about it.
    nonisolated private static func logEntries(_ item: AVPlayerItem, now: Date = Date()) -> [ErrorLogEntry] {
        let events = item.errorLog()?.events ?? []
        let recent: [AVPlayerItemErrorLogEvent]
        if events.allSatisfy({ $0.date == nil }) {
            recent = Array(events.suffix(1))
        } else {
            recent = events.filter { event in event.date.map { now.timeIntervalSince($0) <= 10 } ?? false }
        }
        return recent.map { ErrorLogEntry(domain: $0.errorDomain, status: $0.errorStatusCode, comment: $0.errorComment ?? "") }
    }

    // MARK: network changes

    /// Bans and backoffs earned on the old network path would keep the engine off nodes that work on the new one.
    private func watchNetwork() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        let seen = Locked<(last: PathSignature?, lastUp: PathSignature?)>((nil, nil))
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            let now = PathSignature(up: path.status == .satisfied, interfaces: path.availableInterfaces.map(\.name),
                                    gateways: path.gateways.map { "\($0)" })
            let (last, lastUp) = seen.withLock { value -> (PathSignature?, PathSignature?) in
                defer {
                    value.last = now
                    if now.up { value.lastUp = now }
                }
                return (value.last, value.lastUp)
            }
            guard let last, last != now, now.up else { return }
            let interfaceChanged = lastUp.map { $0.interfaces != now.interfaces || $0.gateways != now.gateways } ?? true
            Task { @MainActor in self?.networkPathChanged(interfaceChanged: interfaceChanged, monitor: monitor) }
        }
        monitor.start(queue: DispatchQueue(label: "bilinative.playback.path"))
        pathMonitor = monitor
    }

    private func networkPathChanged(interfaceChanged: Bool, monitor: NWPathMonitor?) {
        guard let monitor, monitor === pathMonitor else { return }
        Logger.shared.info(.player, "network path changed", ["interfaceChanged": .init(interfaceChanged), "mode": .init(mode.label),
                                                             "session": .init(session != nil)])
        session?.networkChanged(interfaceChanged: interfaceChanged)
    }

    // MARK: signed URL refresh

    private func scheduleRefresh(for choice: TrackChoice, epoch current: Int) {
        refreshTask?.cancel()
        guard let deadline = URLComponents(string: choice.video.baseURL)?.queryItems?.first(where: { $0.name == "deadline" })?.value
            .flatMap(Double.init) else { return }
        let wait = max(30, deadline - Date().timeIntervalSince1970 - 300)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self, let choice = self.choice else { return }
            await self.refreshURLs(for: choice, epoch: current)
        }
    }

    /// Ripper mode only: direct mode's playlists are already in AVPlayer, so its URLs cannot be swapped.
    private func refreshURLs(for choice: TrackChoice, epoch current: Int) async {
        guard current == epoch, let session else { return }
        do {
            let info = try await environment.provider.playURL(quality: selectedQuality)
            guard current == epoch, session === self.session else { return }
            guard let dash = info.dash,
                  let video = dash.video.first(where: { $0.id == choice.video.id && $0.codecid == choice.video.codecid }),
                  let audio = dash.audio.first(where: { $0.id == choice.audio.id }) else {
                Logger.shared.warn(.player, "url refresh found no matching streams")
                return
            }
            session.replaceURLs(.video, primary: video.baseURL, backups: video.backupURLs)
            session.replaceURLs(.audio, primary: audio.baseURL, backups: audio.backupURLs)
            let refreshed = TrackChoice(video: video, audio: audio)
            self.choice = refreshed
            scheduleRefresh(for: refreshed, epoch: current)
        } catch {
            Logger.shared.warn(.player, "url refresh failed", ["error": .init(String(describing: error))])
        }
    }

    // MARK: observers and stats

    private func attachObservers(_ item: AVPlayerItem, epoch current: Int) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            let reason = player.reasonForWaitingToPlay
            Task { @MainActor in self?.timeControlChanged(status, reason: reason, epoch: current) }
        })
        observations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error
            let failure = PlaybackController.classify(error, log: PlaybackController.logEntries(item))
            let detail = String(describing: error)
            Task { @MainActor in await self?.launch { await $0.itemFailed(failure, detail: detail, epoch: current) } }
        })
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.timeJumpedNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeJumped() }
        })
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let failure = PlaybackController.classify(error, log: PlaybackController.logEntries(item))
            let detail = String(describing: error)
            Task { @MainActor in await self?.launch { await $0.itemFailed(failure, detail: detail, epoch: current) } }
        })
        notificationTokens.append(center.addObserver(forName: .localServerStopped, object: environment.server, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.launch { await $0.serverStopped(epoch: current) } }
        })
        notificationTokens.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.session?.dropCache()
                Logger.shared.warn(.player, "memory warning, prefetch cache dropped")
            }
        })
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.newErrorLogEntryNotification, object: item, queue: .main) { _ in
            guard let event = item.errorLog()?.events.last else { return }
            Logger.shared.warn(.player, "error log", ["status": .init(event.errorStatusCode), "domain": .init(event.errorDomain),
                                                      "comment": .init(event.errorComment ?? ""), "uri": .init(event.uri ?? "")])
        })
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.newAccessLogEntryNotification, object: item, queue: .main) { _ in
            guard let event = item.accessLog()?.events.last else { return }
            Logger.shared.info(.player, "access log", ["indicatedBitrate": .init(event.indicatedBitrate.rounded()),
                                                       "observedBitrate": .init(event.observedBitrate.rounded()),
                                                       "stalls": .init(event.numberOfStalls),
                                                       "transferMs": .init((event.transferDuration * 1000).rounded())])
        })
    }

    private func detachObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
    }

    private func tick(_ time: CMTime) {
        guard let session, let item = player.currentItem else { return }
        let seconds = time.seconds.isFinite ? time.seconds : 0
        session.updatePlayhead(seconds: seconds, rate: Double(player.rate))
        let ahead = item.loadedTimeRanges.map(\.timeRangeValue)
            .first { $0.start.seconds <= seconds + 0.5 && $0.end.seconds >= seconds }
            .map { $0.end.seconds - seconds } ?? 0
        session.reportBuffer(aheadSeconds: ahead, playing: player.timeControlStatus == .playing)
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?, epoch current: Int) {
        guard current == epoch else { return }
        switch status {
        case .playing:
            if overlay.firstFrameMs == nil {
                overlay.firstFrameMs = Date().timeIntervalSince(startedAt) * 1000
                Logger.shared.info(.player, "first frame", ["ms": .init(overlay.firstFrameMs!.rounded()), "mode": .init(mode.label)])
            }
            if let seekStartedAt {
                overlay.lastSeekMs = Date().timeIntervalSince(seekStartedAt) * 1000
                Logger.shared.info(.player, "seek resumed", ["ms": .init(overlay.lastSeekMs!.rounded())])
                self.seekStartedAt = nil
            }
            phase = .playing
        case .waitingToPlayAtSpecifiedRate:
            if reason == .toMinimizeStalls, overlay.firstFrameMs != nil, seekStartedAt == nil {
                overlay.stalls += 1
                session?.reportStall()
                Logger.shared.warn(.player, "stall", ["at": .init(currentSeconds.rounded()), "mode": .init(mode.label)])
            }
        default:
            break
        }
    }

    private func timeJumped() {
        guard overlay.firstFrameMs != nil else { return }
        seekStartedAt = Date()
        Logger.shared.info(.player, "seek", ["to": .init(currentSeconds.rounded())])
    }

    private func startStatsLoop() {
        statsTask?.cancel()
        lastDelivered = nil
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.sampleStats()
            }
        }
    }

    /// Ripper mode counts the engine's delivered bytes; direct mode the bytes AVPlayer's access log reports,
    /// so the overlay compares the two modes.
    private func sampleStats() {
        var next = overlay
        let delivered: Int64
        if let session {
            let stats = session.stats()
            next.ripper = stats
            delivered = stats.deliveredBytes
        } else {
            next.ripper = nil
            delivered = player.currentItem?.accessLog()?.events.reduce(Int64(0)) { $0 + $1.numberOfBytesTransferred } ?? 0
        }
        if let lastDelivered { next.downloadBps = Double(max(0, delivered - lastDelivered)) * 2 }
        lastDelivered = delivered
        if next != overlay { overlay = next }
    }

    // MARK: helpers

    private func restart() async {
        let time = currentSeconds
        stop()
        await start(at: time)
    }

    /// Runs playback work as a task that stop() and fail() can cancel.
    private func launch(_ body: @escaping @MainActor (PlaybackController) async -> Void) async {
        workCount += 1
        let id = workCount
        let task = Task { @MainActor in await body(self) }
        work[id] = task
        await task.value
        work[id] = nil
    }

    @discardableResult
    private func advance() -> Int {
        epoch += 1
        return epoch
    }

    private func ensureCurrent(_ current: Int) throws {
        guard current == epoch else { throw CancellationError() }
    }

    private func teardownPlayback() {
        refreshTask?.cancel()
        statsTask?.cancel()
        work.values.forEach { $0.cancel() }
        player.pause()
        detachObservers()
        player.replaceCurrentItem(with: nil)
        teardownSession()
        if let directToken { environment.directLoader.unregister(directToken) }
        directToken = nil
    }

    private func teardownSession() {
        session?.close()
        session = nil
        if let routerToken { environment.router.unregister(routerToken) }
        routerToken = nil
    }
}
