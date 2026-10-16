import AVFoundation
import Foundation
import Observation
import UIKit
import BiliAPI
import AppLogic
import DevLog

@MainActor
@Observable
final class VideoPageModel {
    typealias Account = AppEnvironment.Account

    let route: VideoRoute
    private(set) var detail: VideoDetail?
    private(set) var loadError: String?
    private(set) var current: PlayItem?
    private(set) var controller: PlaybackControlling?
    private(set) var related: [VideoCard] = []
    private(set) var chapters: [Chapter] = []
    private(set) var online: String?
    private(set) var ended = false
    /// Kept across parts and autoplay switches.
    var rate: Float = 1 { didSet { controller?.rate = rate } }
    var mirrored = false
    private(set) var sleepDeadline: Date?
    /// What 定时关闭 was set to, for the panel to show which choice is on.
    private(set) var sleepMinutes: Int?

    @ObservationIgnored let client: BiliClient
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let blockRules: BlockRuleStore?
    @ObservationIgnored let danmaku: DanmakuController
    /// One player for the page's life: each part's controller plays on it, so the layer and picture in picture
    /// stay attached when autoplay moves to the next part.
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored let keeper: PiPKeeper
    @ObservationIgnored private let account: @MainActor () -> Account
    @ObservationIgnored private let makeController: @MainActor (PlayItem, AVPlayer) -> PlaybackControlling
    @ObservationIgnored private let sleep: (Double) async -> Void
    @ObservationIgnored private let onlineInterval: Double
    @ObservationIgnored private let isAppActive: @MainActor () -> Bool

    /// The player surface's host view, handed over by the page so 小窗播放 can start picture in picture on it.
    /// Held for the model's life: picture in picture belongs to its layer, and a page brought back from the
    /// small window shows this same view again.
    @ObservationIgnored var host: PlayerHostView? {
        didSet {
            host?.onPiPActive = { [weak self] in self?.pipChanged($0) }
            host?.onRestore = { [weak self] in
                guard let self else { return false }
                return self.keeper.restore(self)
            }
        }
    }
    /// Picture in picture is playing this page's video.
    @ObservationIgnored private(set) var pipActive = false
    /// The lifecycle of the page view showing this model; an earlier page's late teardown checks it.
    @ObservationIgnored weak var presenter: AnyObject?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var followingRules = false
    @ObservationIgnored private var appeared = false
    /// Another page is pushed over this one: playback is paused, and resumes when the page shows again.
    @ObservationIgnored private(set) var covered = false
    /// The page left the navigation stack and its playback was released.
    @ObservationIgnored private(set) var closed = false
    @ObservationIgnored private var resumeOnShow = false
    /// A part chosen while covered, started when the page shows again.
    @ObservationIgnored private var pendingStart: PendingStart?
    @ObservationIgnored private var keptPosition = 0.0
    /// Chapters fetched while choosing the part, so play does not ask again.
    @ObservationIgnored private var prefetched: (cid: Int64, chapters: [Chapter])?
    /// The open that failed, for 重试.
    @ObservationIgnored private var failedOpen: (bvid: String, cid: Int64?, start: Double?)?
    /// Bumped by every open, so a slow detail answer cannot replace a newer one.
    @ObservationIgnored private var openCount = 0
    @ObservationIgnored private var schedule = HeartbeatSchedule()
    /// The finished heartbeat (-1) went out; a later mark at the end position would overwrite it.
    @ObservationIgnored private var finishedSent = false
    @ObservationIgnored private var heartbeats: Task<Void, Never>?
    @ObservationIgnored private var onlineTask: Task<Void, Never>?
    @ObservationIgnored private var relatedTask: Task<Void, Never>?
    @ObservationIgnored private var chaptersTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?

    /// `makeController` gets the page's player and must play on it.
    init(route: VideoRoute, client: BiliClient, settings: AppSettings, blockRules: BlockRuleStore? = nil,
         account: @escaping @MainActor () -> Account,
         makeController: @escaping @MainActor (PlayItem, AVPlayer) -> PlaybackControlling,
         sleep: @escaping (Double) async -> Void = { seconds in _ = try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) },
         onlineInterval: Double = 30,
         ownHash: @escaping @MainActor () -> String? = { nil },
         isAppActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState != .background },
         keeper: PiPKeeper? = nil) {
        self.route = route
        self.client = client
        self.settings = settings
        self.blockRules = blockRules
        danmaku = DanmakuController(client: client, settings: settings, ownHash: ownHash)
        self.keeper = keeper ?? .shared
        self.account = account
        self.makeController = makeController
        self.sleep = sleep
        self.onlineInterval = onlineInterval
        self.isAppActive = isAppActive
    }

    var pageItems: [PlayItem] {
        guard let detail else { return [] }
        return detail.pages.map { PlayItem(bvid: detail.bvid, cid: $0.cid) }
    }

    var episodeItems: [PlayItem] {
        detail?.season?.sections.flatMap { $0.episodes.map { PlayItem(bvid: $0.bvid, cid: $0.cid) } } ?? []
    }

    var currentPage: VideoPage? {
        guard let current, let detail, detail.bvid == current.bvid else { return nil }
        return detail.pages.first { $0.cid == current.cid }
    }

    // MARK: loading

    func load() async {
        started = true
        followBlockRules()
        // Not awaited: the rules only matter once danmaku arrives, and a slow answer must not delay the video.
        Task { await blockRules?.refresh() }
        await open(bvid: route.bvid, cid: route.cid, start: route.startSeconds)
    }

    /// Keeps the danmaku filter on the shared store's rules, so a rule added from the panel mid-video applies at once.
    private func followBlockRules() {
        guard let blockRules else { return }
        danmaku.rules = blockRules.rules
        guard !followingRules else { return }
        followingRules = true
        observeBlockRules(blockRules)
    }

    private func observeBlockRules(_ store: BlockRuleStore) {
        withObservationTracking {
            _ = store.rules
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.danmaku.rules = store.rules
                self.observeBlockRules(store)
            }
        }
    }

    /// 重试 in the player box: the failed open, or the failed playback at its position.
    func retry() async {
        if let failedOpen {
            await open(bvid: failedOpen.bvid, cid: failedOpen.cid, start: failedOpen.start)
        } else if let controller {
            keeper.willPlay(self)
            await controller.start(at: controller.position, autoplay: true)
        } else {
            await load()
        }
    }

    func switchTo(_ item: PlayItem) async {
        if item.bvid == detail?.bvid {
            await play(item, at: nil)
        } else {
            await open(bvid: item.bvid, cid: item.cid, start: nil)
        }
    }

    private func open(bvid: String, cid: Int64?, start: Double?) async {
        guard !closed else { return }
        openCount += 1
        let attempt = openCount
        loadError = nil
        failedOpen = nil
        ended = false
        do {
            let detail: VideoDetail
            if let loaded = self.detail, loaded.bvid == bvid {
                detail = loaded
            } else {
                stopController(handingOver: true)
                detail = try await client.videoDetail(bvid: bvid)
                guard attempt == openCount else { return }
                related = []
                online = nil
                chapters = []
                self.detail = detail
                fetchRelated(bvid: bvid)
            }
            // Bangumi and other PGC pages answer view with a redirect; their playurl is another API.
            guard detail.redirectURL == nil else { throw PageError.unsupported }
            guard let first = detail.pages.first else { throw PageError.noParts }
            var info: PlayerInfo?
            let chosen: Int64
            if let cid {
                chosen = cid
            } else if detail.pages.count > 1 {
                info = try? await client.playerInfo(bvid: bvid, cid: first.cid)
                guard attempt == openCount else { return }
                let saved = info?.lastPlayCid
                chosen = detail.pages.first { $0.cid == saved }?.cid ?? first.cid
            } else {
                chosen = first.cid
            }
            if let info, chosen == first.cid { prefetched = (chosen, info.chapters) }
            if appeared { startOnlinePoll() }
            await play(PlayItem(bvid: bvid, cid: chosen), at: start)
        } catch is CancellationError {
            return
        } catch {
            guard attempt == openCount else { return }
            Logger.shared.warn(.ui, "video page load failed", ["bvid": .init(bvid), "error": .init(String(describing: error))])
            failedOpen = (bvid, cid, start)
            loadError = Self.message(for: error)
            // The previous video's last frame would show through the failure.
            if controller == nil { player.replaceCurrentItem(with: nil) }
        }
    }

    /// Plays one part in place. Without a start it loads paused, seeks to Bilibili's saved position for
    /// this part and plays, since the saved position only arrives with the playurl answer.
    func play(_ item: PlayItem, at seconds: Double?) async {
        guard !closed else { return }
        if item != current {
            if let prefetched, prefetched.cid == item.cid {
                chapters = prefetched.chapters
            } else {
                fetchChapters(bvid: item.bvid, cid: item.cid)
            }
        }
        prefetched = nil
        stopController(handingOver: true)
        ended = false
        finishedSent = false
        current = item
        danmaku.load(cid: item.cid, bvid: item.bvid, durationMs: Int64(currentPage?.duration ?? 0) * 1000)
        schedule = HeartbeatSchedule()
        let next = makeController(item, player)
        next.rate = rate
        next.onEnd = { [weak self] in
            Task { await self?.handleEnd() }
        }
        next.onPosition = { [weak self] seconds in self?.positionChanged(seconds) }
        controller = next
        if covered {
            pendingStart = PendingStart(seconds: seconds)
            return
        }
        await start(next, item: item, at: seconds)
    }

    private struct PendingStart {
        let seconds: Double?
    }

    private func start(_ next: PlaybackControlling, item: PlayItem, at seconds: Double?) async {
        keeper.willPlay(self)
        if let seconds {
            await next.start(at: seconds, autoplay: true)
        } else {
            await next.start(at: 0, autoplay: false)
            guard controller === next else { return }
            let duration = Double(currentPage?.duration ?? 0)
            let resumeAt = next.resume.map {
                ResumePoint.start(lastPlayTimeMs: $0.timeMs, lastPlayCid: $0.cid, cid: item.cid, duration: duration)
            } ?? 0
            if resumeAt > 0 { await next.seek(to: resumeAt) }
            guard controller === next else { return }
            if covered { resumeOnShow = true } else { next.play() }
        }
        guard controller === next else { return }
        sendHeartbeat(item, schedule.mark(position: next.position))
    }

    func handleEnd() async {
        guard let current, let controller else { return }
        finishedSent = true
        sendHeartbeat(current, HeartbeatSchedule.finished)
        let parts = pageItems.isEmpty ? [current] : pageItems
        switch Autoplay.next(after: current, parts: parts, episodes: episodeItems, autoplay: settings.autoplay, loop: settings.loop) {
        case .replay:
            await replay(controller)
        case .play(let item):
            // In the background without picture in picture the next part would play as audio only.
            guard isAppActive() || pipActive else {
                Logger.shared.info(.ui, "autoplay skipped in the background", ["cid": .init(item.cid)])
                ended = true
                return
            }
            Logger.shared.info(.ui, "autoplay", ["bvid": .init(item.bvid), "cid": .init(item.cid)])
            await switchTo(item)
        case .stop:
            ended = true
        }
    }

    /// 重播 on the end screen, and 单集循环.
    func replay() async {
        guard let controller else { return }
        await replay(controller)
    }

    private func replay(_ controller: PlaybackControlling) async {
        keeper.willPlay(self)
        ended = false
        finishedSent = false
        await controller.seek(to: 0)
        schedule = HeartbeatSchedule()
        controller.play()
    }

    // MARK: player actions (heartbeats go out from here)

    func play() {
        if ended {
            Task { await replay() }
            return
        }
        keeper.willPlay(self)
        controller?.play()
    }

    func pause() {
        guard let controller else { return }
        controller.pause()
        mark()
    }

    func togglePlay() {
        if controller?.isPlaying == true { pause() } else { play() }
    }

    func seek(to seconds: Double) async {
        guard let controller else { return }
        ended = false
        finishedSent = false
        await controller.seek(to: seconds)
        mark()
    }

    // MARK: page lifecycle

    /// The page is on top: the first time it loads, after a cover it resumes if it was playing. It stays paused
    /// without `resuming`, while another page's video plays in the small window.
    func appear(resuming: Bool = true) {
        guard !appeared else { return }
        appeared = true
        guard started else {
            started = true
            Task { await load() }
            return
        }
        if detail != nil { startOnlinePoll() }
        if closed {
            reopen()
            return
        }
        guard covered else { return }
        covered = false
        guard let controller, let current else { return }
        if let pending = pendingStart {
            pendingStart = nil
            Task { await start(controller, item: current, at: pending.seconds) }
        } else if resumeOnShow {
            resumeOnShow = false
            if resuming { play() }
        }
    }

    /// Another page was pushed over this one. It pauses and keeps its controller, position and danmaku, so
    /// going back is instant; the heartbeat reports the paused position.
    func cover() {
        guard appeared else { return }
        appeared = false
        covered = true
        onlineTask?.cancel()
        onlineTask = nil
        // One video at a time: the small window does not go on behind the new page.
        stopPiP()
        guard let controller else { return }
        resumeOnShow = controller.isPlaying
        pause()
    }

    /// The page left the navigation stack: playback stops and is released, and nothing it started goes on.
    func close() {
        guard !closed else { return }
        closed = true
        appeared = false
        covered = false
        resumeOnShow = false
        pendingStart = nil
        // An open still waiting on the network must not start a player for a closed page.
        openCount += 1
        onlineTask?.cancel()
        onlineTask = nil
        setSleepTimer(minutes: nil)
        stopPiP()
        if let controller { keptPosition = controller.position }
        stopController()
    }

    /// The page closed while picture in picture plays its video: playback goes on without a page.
    func continueInPiP() {
        appeared = false
        onlineTask?.cancel()
        onlineTask = nil
    }

    /// A closed page shown again (a restore that lost a race with its release) starts over where it stopped.
    private func reopen() {
        closed = false
        guard let current else {
            Task { await load() }
            return
        }
        let position = keptPosition
        Task { await play(current, at: position) }
    }

    func backgrounded() {
        mark()
    }

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes, minutes > 0 else {
            sleepTask = nil
            sleepDeadline = nil
            sleepMinutes = nil
            return
        }
        sleepMinutes = minutes
        let seconds = Double(minutes) * 60
        let deadline = Date().addingTimeInterval(seconds)
        sleepDeadline = deadline
        let sleep = self.sleep
        sleepTask = Task { [weak self] in
            await sleep(seconds)
            guard !Task.isCancelled, let self, self.sleepDeadline == deadline else { return }
            Logger.shared.info(.ui, "sleep timer fired")
            self.pause()
            self.sleepDeadline = nil
            self.sleepMinutes = nil
        }
    }

    func startPiP() {
        host?.startPiP()
    }

    func stopPiP() {
        guard pipActive else { return }
        host?.stopPiP()
    }

    /// From the host view's picture in picture delegate; tests set it directly, since the simulator has no PiP.
    func pipChanged(_ active: Bool) {
        guard active != pipActive else { return }
        pipActive = active
        if !active { keeper.pipStopped(self) }
    }

    // MARK: heartbeats

    private func positionChanged(_ seconds: Double) {
        guard let current, let controller, !finishedSent else { return }
        if let played = schedule.tick(position: seconds, playing: controller.isPlaying) {
            sendHeartbeat(current, played)
        }
    }

    private func mark() {
        guard let current, let controller, !finishedSent else { return }
        sendHeartbeat(current, schedule.mark(position: controller.position))
    }

    /// Sent one after another, so a late answer never reorders the history Bilibili keeps.
    private func sendHeartbeat(_ item: PlayItem, _ played: Int) {
        guard case .loggedIn = account() else { return }
        let previous = heartbeats
        let client = self.client
        heartbeats = Task {
            await previous?.value
            do {
                try await client.heartbeat(bvid: item.bvid, cid: item.cid, playedTime: played)
            } catch {
                Logger.shared.warn(.api, "heartbeat failed", ["played": .init(played), "error": .init(String(describing: error))])
            }
        }
    }

    /// Waits for the heartbeats sent so far.
    func settleHeartbeats() async {
        await heartbeats?.value
    }

    // MARK: side loads

    private func stopController(handingOver: Bool = false) {
        guard let controller else { return }
        mark()
        controller.onEnd = nil
        controller.onPosition = nil
        if handingOver { controller.handOver() } else { controller.stop() }
        self.controller = nil
    }

    private func fetchRelated(bvid: String) {
        let client = self.client
        relatedTask?.cancel()
        relatedTask = Task { [weak self] in
            do {
                let cards = try await client.related(bvid: bvid)
                guard let self, self.detail?.bvid == bvid else { return }
                self.related = cards
            } catch is CancellationError {
                return
            } catch {
                Logger.shared.warn(.api, "related failed", ["error": .init(String(describing: error))])
            }
        }
    }

    private func fetchChapters(bvid: String, cid: Int64) {
        let client = self.client
        chapters = []
        chaptersTask?.cancel()
        chaptersTask = Task { [weak self] in
            do {
                let info = try await client.playerInfo(bvid: bvid, cid: cid)
                guard let self, self.current?.cid == cid else { return }
                self.chapters = info.chapters
            } catch is CancellationError {
                return
            } catch {
                Logger.shared.warn(.api, "player info failed", ["error": .init(String(describing: error))])
            }
        }
    }

    private func startOnlinePoll() {
        onlineTask?.cancel()
        let interval = onlineInterval
        onlineTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnline()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if self == nil { return }
            }
        }
    }

    private func refreshOnline() async {
        guard let detail, let current else { return }
        do {
            let total = try await client.onlineCount(aid: detail.aid, bvid: current.bvid, cid: current.cid)
            if self.current == current { online = total }
        } catch {
            Logger.shared.warn(.api, "online count failed", ["error": .init(String(describing: error))])
        }
    }

    enum PageError: Error {
        case noParts, unsupported
    }

    static func message(for error: Error) -> String {
        switch error as? PageError {
        case .noParts?: return "该视频没有可播放的分P"
        case .unsupported?: return "暂不支持播放此类视频"
        case nil: break
        }
        if let error = error as? BiliError { return error.userMessage }
        if error is URLError { return "网络连接失败，请检查网络后重试" }
        return "加载失败，请稍后重试"
    }
}
