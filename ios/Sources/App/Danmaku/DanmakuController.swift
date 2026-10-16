import Foundation
import Observation
import BiliAPI
import Danmaku
import DevLog

/// One part's danmaku: segments fetched as the playhead nears them, filtered, and handed to the view in
/// video time.
@MainActor
@Observable
final class DanmakuController {
    /// The uploader closed danmaku for this video.
    private(set) var closed = false
    /// The account's block list, set by the block rule store.
    var rules: [BlockRule] = [] {
        didSet { if rules != oldValue { rebuild() } }
    }
    /// Bumped whenever what is on screen no longer matches: a new part, or a filter or block list change.
    @ObservationIgnored private(set) var generation = 0

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let ownHash: @MainActor () -> String?

    @ObservationIgnored private var cid: Int64 = 0
    @ObservationIgnored private var bvid = ""
    @ObservationIgnored private var durationMs: Int64 = 0
    /// Bumped by every load, so a segment for the previous part is dropped.
    @ObservationIgnored private var loadCount = 0
    /// Loaded, in flight or failed: `needed` skips them.
    @ObservationIgnored private var attempted: Set<Int> = []
    @ObservationIgnored private var failed: Set<Int> = []
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var segments: [Int: [DanmakuElem]] = [:]
    @ObservationIgnored private var own: [DisplayDanmaku] = []
    @ObservationIgnored private var timeline = DanmakuTimeline()
    @ObservationIgnored private var appliedFilter = DanmakuFilterOptions()
    /// Items the timeline will not emit because the playhead had already passed them: own danmaku, and a
    /// segment that arrived late.
    @ObservationIgnored private var immediate: [DisplayDanmaku] = []
    @ObservationIgnored private var lastMs: Int64?
    @ObservationIgnored private var needsCatchUp = true
    @ObservationIgnored private var lastSegment = 0

    init(client: BiliClient, settings: AppSettings, ownHash: @escaping @MainActor () -> String?) {
        self.client = client
        self.settings = settings
        self.ownHash = ownHash
    }

    /// Resets everything for a new part.
    func load(cid: Int64, bvid: String, durationMs: Int64) {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        loadCount += 1
        self.cid = cid
        self.bvid = bvid
        self.durationMs = durationMs
        attempted = []
        failed = []
        segments = [:]
        own = []
        immediate = []
        timeline = DanmakuTimeline()
        appliedFilter = settings.danmaku.filter
        lastMs = nil
        needsCatchUp = true
        lastSegment = 0
        closed = false
        generation += 1
    }

    /// Called on every display-link frame.
    func update(positionMs: Int64, playing: Bool) {
        guard cid != 0, !closed else { return }
        if settings.danmaku.filter != appliedFilter { rebuild() }
        let segment = DanmakuSegments.index(forMs: positionMs)
        if segment != lastSegment {
            lastSegment = segment
            retryFailed()
        }
        for index in DanmakuSegments.needed(atMs: positionMs, loaded: attempted, durationMs: durationMs)
        where playing || index == segment {
            fetch(index)
        }
    }

    /// The view cleared the screen (a seek, a new size or new settings): the next `pendingItems` re-lays
    /// what would be on screen at that time.
    func seeked(toMs ms: Int64) {
        lastSegment = DanmakuSegments.index(forMs: ms)
        retryFailed()
        needsCatchUp = true
    }

    func showOwn(_ draft: DanmakuDraft) {
        let elem = DanmakuElem(progressMs: lastMs ?? draft.progressMs, mode: draft.mode, fontSize: draft.fontSize,
                               color: draft.color, midHash: ownHash() ?? "", content: draft.text,
                               ctime: Int64(Date().timeIntervalSince1970), colorful: draft.gradient ? 60001 : 0)
        let item = DisplayDanmaku(elem: elem, text: draft.text, isOwn: true)
        own.append(item)
        // In the timeline too, so a seek back shows it again; at the playhead it is not emitted twice.
        timeline.add([item])
        immediate.append(item)
    }

    /// Drains what the view should place now: everything since the last call, or after a seek what would
    /// still be on screen, with the danmaku's own start time so it is placed mid-flight.
    func pendingItems(atMs requested: Int64) -> [DisplayDanmaku] {
        guard !closed else { return [] }
        var ms = requested
        // The timeline takes any step back as a seek and would replay; jitter without a seek holds still.
        if !needsCatchUp, let lastMs, ms < lastMs, lastMs - ms < 200 { ms = lastMs }
        var items: [DisplayDanmaku]
        if needsCatchUp || lastMs == nil {
            needsCatchUp = false
            immediate = []
            items = catchUp(to: ms)
        } else {
            items = timeline.advance(to: ms)
            if !immediate.isEmpty {
                items.append(contentsOf: immediate)
                immediate = []
            }
        }
        lastMs = ms
        return items
    }

    /// Waits for the segment requests in flight (tests).
    func settle() async {
        for _ in 0..<10 {
            let pending = Array(tasks.values)
            if pending.isEmpty { return }
            for task in pending { await task.value }
        }
    }

    private var lookbackMs: Int64 {
        Int64(max(settings.danmaku.scrollDuration, 4) * 1000)
    }

    /// The timeline counts any step over a second as a jump and emits nothing, so it is walked in steps.
    private func catchUp(to ms: Int64) -> [DisplayDanmaku] {
        var cursor = max(ms - lookbackMs, -1)
        timeline.seek(to: cursor)
        var items: [DisplayDanmaku] = []
        while cursor < ms {
            cursor = min(cursor + 1_000, ms)
            items.append(contentsOf: timeline.advance(to: cursor))
        }
        return items
    }

    private func retryFailed() {
        guard !failed.isEmpty else { return }
        attempted.subtract(failed)
        failed = []
    }

    private func fetch(_ index: Int) {
        attempted.insert(index)
        let client = self.client
        let cid = self.cid
        let load = loadCount
        tasks[index] = Task { [weak self] in
            let result: Result<DanmakuSegment, Error>
            do {
                result = .success(try await client.danmakuSegment(cid: cid, index: index))
            } catch {
                result = .failure(error)
            }
            self?.finished(index, load: load, result)
        }
    }

    private func finished(_ index: Int, load: Int, _ result: Result<DanmakuSegment, Error>) {
        guard load == loadCount else { return }
        tasks[index] = nil
        switch result {
        case .success(let segment):
            // DanmakuTimeline does not dedupe, so a segment must only ever be added once.
            guard segments[index] == nil else { return }
            received(segment, index: index)
        case .failure(let error):
            if error is CancellationError { return }
            Logger.shared.warn(.api, "danmaku segment failed", ["index": .init(index), "error": .init(String(describing: error))])
            failed.insert(index)
        }
    }

    private func received(_ segment: DanmakuSegment, index: Int) {
        if segment.closed {
            Logger.shared.info(.player, "danmaku closed by the uploader", ["bvid": .init(bvid)])
            closed = true
            for task in tasks.values { task.cancel() }
            tasks = [:]
            timeline = DanmakuTimeline()
            immediate = []
            generation += 1
            return
        }
        segments[index] = segment.elems
        let items = filtered(segment.elems)
        Logger.shared.info(.player, "danmaku segment", ["index": .init(index), "count": .init(segment.elems.count), "shown": .init(items.count)])
        timeline.add(items)
        guard let lastMs, !needsCatchUp else { return }
        let from = lastMs - lookbackMs
        immediate.append(contentsOf: items.lazy.filter { $0.elem.progressMs > from && $0.elem.progressMs <= lastMs })
    }

    private func filtered(_ elems: [DanmakuElem]) -> [DisplayDanmaku] {
        DanmakuFilter.apply(elems, options: appliedFilter, rules: rules, ownHash: ownHash())
    }

    /// A filter or block list change re-filters every loaded segment, and the view re-lays the screen.
    private func rebuild() {
        appliedFilter = settings.danmaku.filter
        guard cid != 0, !closed else { return }
        timeline = DanmakuTimeline()
        let all = segments.keys.sorted().flatMap { segments[$0] ?? [] }
        timeline.add(filtered(all) + own)
        immediate = []
        needsCatchUp = true
        generation += 1
    }
}
