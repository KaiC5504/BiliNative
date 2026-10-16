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
    /// Direct mode's header requests: not the engine's warm connections, which would favour direct mode.
    let directTransport: RangeTransport
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
    /// Signed URLs are refreshed this long before their deadline, and count as stale within it.
    nonisolated private static let urlMarginSeconds = 300.0
    private static let refreshRetrySeconds = 30.0
    /// A local server that stops again this soon after being restarted is left for direct mode.
    private static let serverRestartSeconds = 30.0

    /// The page's player, shared by every part it plays, so the layer and picture in picture stay attached.
    let player: AVPlayer
    private(set) var mode: Mode = .ripper
    private(set) var phase: Phase = .idle
    private(set) var qualities: [QualityOption] = []
    private(set) var selectedQuality: Int
    /// The stream actually chosen; selectedQuality is only the ceiling asked for.
    private(set) var playing: PlayingStream?
    private(set) var codec: VideoCodec
    private(set) var btrEnabled: Bool
    private(set) var overlay = OverlayStats()
    /// Bilibili's saved position for this video, from the first playurl answer of a start.
    private(set) var resume: (timeMs: Int64, cid: Int64)?
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    /// End of the loaded range that holds the playhead, in seconds.
    private(set) var buffered: Double = 0
    /// Playing or waiting to play; false only when paused or stopped.
    private(set) var isPlaying = false
    private(set) var videoSize: CGSize?
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if player.rate > 0 { player.rate = rate }
        }
    }
    @ObservationIgnored var onEnd: (@MainActor () -> Void)?
    @ObservationIgnored var onPosition: (@MainActor (Double) -> Void)?

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
    @ObservationIgnored private var seekTimer = SeekTimer()
    @ObservationIgnored private var stallFilter = StallFilter()
    @ObservationIgnored private var refreshedAfterFatal = false
    @ObservationIgnored private var refreshingAfterFatal = false
    @ObservationIgnored private var lastDelivered: Int64?
    /// Bumped by every stop, restart, switch and failure; async work and callbacks of an older epoch do nothing.
    @ObservationIgnored private var epoch = 0
    /// Codec kinds that failed in this playback only: not AVFoundation's verdict on the phone.
    @ObservationIgnored private var rejectedHere: Set<String> = []
    /// Codec kinds whose unexplained failure already got one retry with fresh URLs.
    @ObservationIgnored private var unknownRetried: Set<String> = []
    @ObservationIgnored private var lastNetworkRestart: Date?
    /// Set once this playback left BTR mode; later restarts stay direct.
    @ObservationIgnored private var forcedDirect = false
    /// The position to report while no item is loaded, so a retry resumes where playback stopped.
    @ObservationIgnored private var heldPosition = 0.0
    /// The video sample entry in Bilibili's bytes of the current choice, once its headers were read.
    @ObservationIgnored private var sourceEntry: String?
    /// Whether a load starts playback; reloading a player the user paused leaves it paused.
    @ObservationIgnored private var playWhenLoaded = true
    @ObservationIgnored private var lastServerRestart: Date?
    /// The current item reached .playing; a format failure after that is not a codec refusal.
    @ObservationIgnored private var itemPlayed = false
    @ObservationIgnored private var sawFirstFrame = false
    /// False when this playback's first frame waited on the user (loaded paused), so its time means nothing.
    @ObservationIgnored private var firstFrameTimed = true
    @ObservationIgnored private var loggedPlayURL = false
    @ObservationIgnored private var loadedAt: Date?
    /// The item this controller put on the player. Until it loads one, the player may still hold the previous
    /// part's last frame, which is not this controller's to play or measure.
    @ObservationIgnored private var loadedItem: AVPlayerItem?

    init(environment: PlaybackEnvironment, quality: Int, codec: VideoCodec, btrEnabled: Bool, player: AVPlayer = AVPlayer()) {
        self.environment = environment
        self.player = player
        selectedQuality = quality
        self.codec = codec
        self.btrEnabled = btrEnabled
        player.automaticallyWaitsToMinimizeStalling = true
    }

    var playingQuality: Int? { playing?.quality }

    private var ownsItem: Bool {
        guard let loadedItem else { return false }
        return player.currentItem === loadedItem
    }

    var currentSeconds: Double {
        guard ownsItem else { return heldPosition }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    // MARK: public actions

    func start(at time: Double = 0) async {
        await startPlayback(at: time, autoplay: true)
    }

    func start(at time: Double, autoplay: Bool) async {
        await startPlayback(at: time, autoplay: autoplay)
    }

    func play() {
        playWhenLoaded = true
        // The page loads paused, seeks to the resume point and plays at once: that is still startup time.
        if !sawFirstFrame, let loadedAt, Date().timeIntervalSince(loadedAt) < 2 { firstFrameTimed = true }
        guard ownsItem else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        playWhenLoaded = false
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) async {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        position = target
        guard ownsItem else {
            heldPosition = target
            return
        }
        _ = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func startPlayback(at time: Double, autoplay: Bool) async {
        rejectedHere = []
        unknownRetried = []
        lastNetworkRestart = nil
        lastServerRestart = nil
        forcedDirect = false
        loggedPlayURL = false
        resume = nil
        playWhenLoaded = autoplay
        isPlaying = autoplay
        seekTimer.cancel()
        sawFirstFrame = false
        firstFrameTimed = true
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
        stop(keepingFrame: false)
    }

    /// Stops for the next part on the same player: the last frame stays up, and picture in picture with it,
    /// until the next part's item replaces it.
    func handOver() {
        stop(keepingFrame: true)
    }

    private func stop(keepingFrame: Bool) {
        heldPosition = currentSeconds
        advance()
        teardownPlayback(keepingFrame: keepingFrame)
        pathMonitor?.cancel()
        pathMonitor = nil
        playing = nil
        isPlaying = false
        phase = .idle
    }

    #if DEBUG
    /// Without `restartable` the server counts as one iOS will not let listen again.
    func debugKillServer(restartable: Bool = false) {
        environment.server.stop()
        let current = epoch
        Task { await launch { await $0.serverStopped(epoch: current, mayRestart: restartable) } }
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
        playing = nil
        sourceEntry = nil
        do {
            let info = try await environment.provider.playURL(quality: selectedQuality)
            try ensureCurrent(current)
            qualities = info.qualityOptions
            if !loggedPlayURL {
                loggedPlayURL = true
                resume = (info.lastPlayTimeMs, info.lastPlayCid)
                Logger.shared.info(.player, "playurl", Self.playURLSummary(info).mapValues { LogValue($0) })
            }
            guard let dash = info.dash else { throw BiliError.notDash }
            let ripper = try await ripperAvailable(epoch: current)
            let choice = try pickTracks(dash, skipHEV1: !ripper && environment.codecMemory.hev1LabelsHoldHEV1)
            self.choice = choice
            playing = PlayingStream(choice.video)
            if choice.video.width > 0, choice.video.height > 0 {
                videoSize = CGSize(width: choice.video.width, height: choice.video.height)
            }
            Logger.shared.info(.player, "choice", ["quality": .init(choice.video.id), "codecs": .init(choice.video.codecs),
                                                   "kbps": .init(choice.video.bandwidth / 1000), "audio": .init(choice.audio.id),
                                                   "node": .init(NodeCatalog.nodeKey(of: choice.video.baseURL)), "btr": .init(ripper)])
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

    /// iOS reclaims a suspended app's listening socket, sometimes without the listener noticing, so a server
    /// that stopped or no longer answers is started again before a BTR playback settles for direct mode.
    private func ripperAvailable(epoch current: Int) async throws -> Bool {
        guard btrEnabled, !forcedDirect else { return false }
        let server = environment.server
        if server.isRunning, !(await server.answers()) {
            Logger.shared.warn(.server, "ready but not answering, starting a new listener", ["port": .init(Int(server.port ?? 0))])
            server.abandonListener()
        }
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
    /// cannot rename hev1 to hvc1, and AVPlayer refuses hev1, so once hev1 labels proved to hold hev1
    /// those streams are skipped up front.
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

    /// Direct mode serves Bilibili's bytes unchanged: a hev1 label plays only when the bytes hold hvc1.
    nonisolated static func directCanPlay(_ stream: DashStream, sourceEntry: String?) -> Bool {
        !isHEV1(stream) || sourceEntry == "hvc1"
    }

    nonisolated static func urlDeadline(_ stream: DashStream) -> Double? {
        URLComponents(string: stream.baseURL)?.queryItems?.first { $0.name == "deadline" }?.value.flatMap(Double.init)
    }

    nonisolated static func urlsNearExpiry(_ choice: TrackChoice, now: Date) -> Bool {
        guard let deadline = urlDeadline(choice.video) else { return false }
        return deadline - now.timeIntervalSince1970 < urlMarginSeconds
    }

    /// What the playurl answer offered, for the log: qualities, codecs and hosts, never a URL.
    nonisolated static func playURLSummary(_ info: PlayURLInfo) -> [String: String] {
        func hosts(_ streams: [DashStream]) -> String {
            let all = streams.flatMap { [$0.baseURL] + $0.backupURLs }.compactMap { URL(string: $0)?.host }
            return Set(all).sorted().joined(separator: ",")
        }
        let video = info.dash?.video ?? []
        return [
            "accept": info.acceptQuality.map(String.init).joined(separator: ","),
            "streams": video.map { "\($0.id):\($0.codecs)" }.joined(separator: ","),
            "videoHosts": hosts(video),
            "audioHosts": hosts(info.dash?.audio ?? []),
            "durl": String(info.hasDurl),
        ]
    }

    private enum Reroute: Error {
        /// Direct mode got a stream whose hev1 label holds a real hev1 entry: choose again without one.
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
            noteSourceEntry(prepared, of: choice)
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
            if !Self.directCanPlay(choice.video, sourceEntry: sourceEntry) { throw Reroute.directWithoutHEV1 }
            try await startDirect(choice, at: time, fallback: true, epoch: current)
        }
    }

    private func startDirect(_ choice: TrackChoice, at time: Double, fallback: Bool, epoch current: Int) async throws {
        let transport = environment.directTransport
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
        noteSourceEntry(prepared, of: choice)
        if !Self.directCanPlay(choice.video, sourceEntry: prepared.sourceEntry) {
            Logger.shared.info(.player, "hev1 label holds hev1, choosing again for direct mode")
            throw Reroute.directWithoutHEV1
        }
        teardownSession()
        if let directToken { environment.directLoader.unregister(directToken) }
        let token = PlaybackRouter.makeToken()
        directToken = token
        let url = environment.directLoader.register(token: token, playlists: PlaybackBuilder.directPlaylists(prepared, token: token))
        mode = fallback ? .directFallback : .direct
        try await load(url: url, viaLoader: true, at: time, epoch: current)
    }

    private func noteSourceEntry(_ prepared: PreparedPlayback, of choice: TrackChoice) {
        sourceEntry = prepared.sourceEntry
        guard Self.isHEV1(choice.video) else { return }
        if prepared.sourceEntry == "hev1" { environment.codecMemory.noteHEV1Entry() }
        Logger.shared.info(.player, "hev1 label", ["entry": .init(prepared.sourceEntry ?? "none"), "rewritten": .init(prepared.rewroteHEV1)])
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
        seekTimer.reloadBegan()
        itemPlayed = false
        // Loaded paused, the first frame waits on the user: that wait is not startup time.
        if !playWhenLoaded, !sawFirstFrame { firstFrameTimed = false }
        attachObservers(item, epoch: current)
        player.replaceCurrentItem(with: item)
        loadedItem = item
        loadedAt = Date()
        position = time
        player.defaultRate = rate
        if time > 0 {
            _ = await player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            try ensureCurrent(current)
        }
        isPlaying = playWhenLoaded
        if playWhenLoaded {
            player.play()
        } else {
            phase = .playing
        }
        startStatsLoop()
        Logger.shared.info(.player, "load", ["mode": .init(mode.label), "at": .init(time), "play": .init(playWhenLoaded)])
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
        rememberPause()
        await fallBackToDirect(reason: "btr failed again", epoch: current)
    }

    /// iOS reclaims a suspended app's listening socket. The server is started again and BTR playback
    /// reloaded; direct mode is for a server that does not come back.
    private func serverStopped(epoch current: Int, mayRestart: Bool = true) async {
        guard current == epoch, mode == .ripper else { return }
        rememberPause()
        if mayRestart, claimServerRestart() {
            let time = currentSeconds
            Logger.shared.warn(.player, "local server stopped, reloading btr", ["at": .init(time)])
            // begin starts the server again, and plays direct (fallback) when that fails.
            await begin(at: time)
            return
        }
        await fallBackToDirect(reason: "local server stopped", epoch: current)
    }

    private func claimServerRestart() -> Bool {
        if let last = lastServerRestart, Date().timeIntervalSince(last) < Self.serverRestartSeconds { return false }
        lastServerRestart = Date()
        return true
    }

    /// Reloads keep a user's pause. Not used for failed items: AVPlayer stops for those by itself.
    private func rememberPause() {
        if ownsItem, phase == .playing { playWhenLoaded = player.rate > 0 }
    }

    private func fallBackToDirect(reason: String, epoch current: Int) async {
        guard current == epoch, let choice else { return }
        let next = advance()
        refreshTask?.cancel()
        forcedDirect = true
        phase = .loading
        let time = currentSeconds
        let expiring = Self.urlsNearExpiry(choice, now: Date())
        Logger.shared.warn(.player, "fallback to direct", ["reason": .init(reason), "at": .init(time), "urlsExpiring": .init(expiring)])
        if expiring || !Self.directCanPlay(choice.video, sourceEntry: sourceEntry) {
            await begin(at: time)
            return
        }
        do {
            try await startDirect(choice, at: time, fallback: true, epoch: next)
        } catch {
            await handle(error, at: time, epoch: next)
        }
    }

    enum ItemFailureReaction: Equatable {
        case fallBackToDirect
        case nextCodec(remember: Bool)
        /// Fresh URLs, unless a restart happened recently.
        case restart
        /// Fresh URLs once per codec, then the next codec.
        case restartOnceThenNextCodec
    }

    /// BTR mode serves an init AVPlayer can read (hev1 renamed to hvc1), so a format failure there is
    /// AVFoundation's verdict on the codec, and the same quality is tried in the next codec, still in BTR mode.
    /// A codec is refused at load; a format failure after the item played (-11821 after background or picture
    /// in picture, or bad bytes from the engine) only moves this playback to the next codec.
    nonisolated static func reaction(to failure: ItemFailure, in mode: Mode, sourceEntry: String?, played: Bool) -> ItemFailureReaction {
        switch (failure, mode) {
        case (.format, _) where played: return .nextCodec(remember: false)
        case (.format, .ripper): return .nextCodec(remember: true)
        case (_, .ripper): return .fallBackToDirect
        case (.network, _): return .restart
        case (.unknown, _): return .restartOnceThenNextCodec
        // A hev1 entry served unpatched says nothing about what this phone can decode.
        case (.format, _): return .nextCodec(remember: sourceEntry != "hev1")
        }
    }

    private func itemFailed(_ failure: ItemFailure, detail: String, epoch current: Int) async {
        guard current == epoch, let choice else { return }
        Logger.shared.error(.player, "item failed", ["mode": .init(mode.label), "kind": .init(String(describing: failure)),
                                                     "error": .init(detail)])
        let time = currentSeconds
        let kind = TrackSelector.codecKind(choice.video)
        switch Self.reaction(to: failure, in: mode, sourceEntry: sourceEntry, played: itemPlayed) {
        case .fallBackToDirect:
            await fallBackToDirect(reason: "item failed in btr mode", epoch: current)
        case .nextCodec(let remember):
            await nextCodec(rejecting: kind, remember: remember, at: time)
        case .restart:
            guard claimNetworkRestart() else { return fail(PlaybackFailure.network) }
            Logger.shared.warn(.player, "restarting with fresh urls", ["at": .init(time)])
            await begin(at: time)
        case .restartOnceThenNextCodec:
            // Unexplained failures are often expired URLs: one fresh start before the codec is blamed.
            if !unknownRetried.contains(kind), claimNetworkRestart() {
                unknownRetried.insert(kind)
                Logger.shared.warn(.player, "unexplained failure, restarting with fresh urls", ["at": .init(time), "kind": .init(kind)])
                await begin(at: time)
            } else {
                await nextCodec(rejecting: kind, remember: false, at: time)
            }
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
        Logger.shared.warn(.player, "codec failed", ["kind": .init(kind), "remembered": .init(remember), "mode": .init(mode.label)])
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
        playing = nil
        isPlaying = false
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

    private func scheduleRefresh(for choice: TrackChoice, epoch current: Int, retry: Bool = false) {
        refreshTask?.cancel()
        let wait: Double
        if retry {
            wait = Self.refreshRetrySeconds
        } else {
            guard let deadline = Self.urlDeadline(choice.video) else { return }
            wait = max(30, deadline - Date().timeIntervalSince1970 - Self.urlMarginSeconds)
        }
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
            Logger.shared.warn(.player, "url refresh failed, retrying", ["error": .init(String(describing: error)),
                                                                          "seconds": .init(Self.refreshRetrySeconds)])
            if current == epoch, session === self.session { scheduleRefresh(for: choice, epoch: current, retry: true) }
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
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, current == self.epoch else { return }
                self.isPlaying = false
                self.onEnd?()
            }
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
        guard let item = player.currentItem else { return }
        let seconds = time.seconds.isFinite ? time.seconds : 0
        updateTimes(item, at: seconds)
        onPosition?(seconds)
        if let ms = seekTimer.ticked(position: seconds, rate: player.rate, playing: player.timeControlStatus == .playing, at: Date()) {
            seekResumed(ms, via: "playhead")
        }
        guard let session else { return }
        session.updatePlayhead(seconds: seconds, rate: Double(player.rate))
        let ahead = item.loadedTimeRanges.map(\.timeRangeValue)
            .first { $0.start.seconds <= seconds + 0.5 && $0.end.seconds >= seconds }
            .map { $0.end.seconds - seconds } ?? 0
        session.reportBuffer(aheadSeconds: ahead, playing: player.timeControlStatus == .playing)
    }

    /// Assigned only on change: every observed write redraws the views reading it, four times a second.
    private func updateTimes(_ item: AVPlayerItem, at seconds: Double) {
        if position != seconds { position = seconds }
        let total = item.duration.seconds
        if total.isFinite, total > 0, duration != total { duration = total }
        let loaded = item.loadedTimeRanges.map(\.timeRangeValue)
            .first { $0.start.seconds <= seconds + 0.5 && $0.end.seconds >= seconds }
            .map(\.end.seconds) ?? seconds
        if abs(buffered - loaded) >= 0.25 { buffered = loaded }
        let playing = player.timeControlStatus != .paused
        if isPlaying != playing { isPlaying = playing }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?, epoch current: Int) {
        guard current == epoch else { return }
        switch status {
        case .playing:
            playWhenLoaded = true
            itemPlayed = true
            isPlaying = true
            if !sawFirstFrame {
                sawFirstFrame = true
                let ms = Date().timeIntervalSince(startedAt) * 1000
                if firstFrameTimed { overlay.firstFrameMs = ms }
                Logger.shared.info(.player, "first frame", ["ms": .init(ms.rounded()), "timed": .init(firstFrameTimed), "mode": .init(mode.label),
                                                            "quality": .init(choice?.video.id ?? 0), "codecs": .init(choice?.video.codecs ?? ""),
                                                            "kbps": .init((choice?.video.bandwidth ?? 0) / 1000),
                                                            "audioKbps": .init((choice?.audio.bandwidth ?? 0) / 1000)])
            }
            if let ms = seekTimer.playing(at: Date()) { seekResumed(ms, via: "status") }
            phase = .playing
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = true
            if reason == .toMinimizeStalls, sawFirstFrame, !seekTimer.isRunning {
                session?.reportStall()
                let stalledAt = Date()
                let position = currentSeconds
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(StallFilter.after * 1_000_000_000))
                    guard let self, current == self.epoch else { return }
                    let fields: [String: LogValue] = ["at": .init(position.rounded()), "mode": .init(self.mode.label)]
                    if self.stallFilter.isSeekWait(stalledAt: stalledAt) {
                        Logger.shared.info(.player, "seek wait", fields)
                    } else {
                        self.overlay.stalls += 1
                        Logger.shared.warn(.player, "stall", fields)
                    }
                }
            }
        case .paused:
            seekTimer.paused()
            isPlaying = false
        default:
            break
        }
    }

    private func timeJumped() {
        stallFilter.jumped(at: Date())
        guard sawFirstFrame else { return }
        let position = currentSeconds
        let timed = seekTimer.jumped(to: position, at: Date(), rate: player.rate)
        Logger.shared.info(.player, "seek", ["to": .init(position.rounded()), "mode": .init(mode.label), "timed": .init(timed)])
    }

    private func seekResumed(_ ms: Double, via: String) {
        overlay.lastSeekMs = ms
        overlay.worstSeekMs = max(overlay.worstSeekMs ?? 0, ms)
        let lag = StallFilter.isLag(seekMs: ms)
        if lag { overlay.stalls += 1 }
        Logger.shared.info(.player, "seek resumed", ["ms": .init(ms.rounded()), "mode": .init(mode.label), "via": .init(via),
                                                     "lag": .init(lag)])
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

    /// A user's pause survives a quality, codec or BTR change.
    private func restart() async {
        let time = currentSeconds
        let autoplay = phase == .playing ? player.rate > 0 : true
        stop()
        await startPlayback(at: time, autoplay: autoplay)
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

    private func teardownPlayback(keepingFrame: Bool = false) {
        refreshTask?.cancel()
        statsTask?.cancel()
        seekTimer.cancel()
        work.values.forEach { $0.cancel() }
        player.pause()
        detachObservers()
        if !keepingFrame { player.replaceCurrentItem(with: nil) }
        loadedItem = nil
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
