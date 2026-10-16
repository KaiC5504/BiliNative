import Foundation
import BiliShared
import DevLog

public enum TrackKind: String, Sendable, Hashable, CaseIterable {
    case video, audio
}

public struct TrackHeaders: Sendable {
    /// Bytes 0 through the end of the SIDX: init segment plus index.
    public let bytes: [UInt8]
    public let totalSize: Int64
}

/// One playback: both tracks' resolvers, the shared connection pool, the segment cache and prefetch.
///
/// Lock order: the connection pool evaluates deadline closures under its own lock, so those read only
/// `playback`, and nothing calls the pool, the downloader or the automatic connection count while
/// holding `state`.
public final class RipperSession: @unchecked Sendable {
    private struct CacheKey: Hashable {
        let track: TrackKind
        let range: ByteRange
    }

    private struct CacheEntry {
        let bytes: [UInt8]
        let endTime: Double
    }

    private struct State {
        var headers: [TrackKind: TrackHeaders] = [:]
        var segments: [TrackKind: [MediaSegment]] = [:]
        /// Position in `segments` by range start.
        var segmentAt: [TrackKind: [Int64: Int]] = [:]
        var cache: [CacheKey: CacheEntry] = [:]
        var inflight: [CacheKey: Task<[UInt8], Error>] = [:]
        /// Segments a player request is downloading or waiting on, with how many requests; prefetch leaves them alone.
        var playerPending: [CacheKey: Int] = [:]
        var reads: [UInt64: Task<Void, Never>] = [:]
        var nextReadID: UInt64 = 0
        var lastRequest: [TrackKind: ByteRange] = [:]
        var requests: UInt64 = 0
        /// Requests numbered up to this were already covered by an `onFatal` call.
        var fatalCovered: UInt64 = 0
        /// For tests.
        var seeks = 0
        var closed = false
    }

    private let state = Locked(State())
    private let playback = Locked((seconds: 0.0, rate: 1.0))
    private let resolvers: [TrackKind: Resolver]
    private let downloader: RangeDownloader
    private let ctx: EngineContext
    private let bans = BanList()
    private let fatalHandler = Locked<((Error) -> Void)?>(nil)

    /// A player request failed after every retry: the app refreshes the URLs or falls back to direct
    /// mode. Requests that fail together are reported once; a request made after a report can report again.
    public var onFatal: ((Error) -> Void)? {
        get { fatalHandler.current }
        set { fatalHandler.withLock { $0 = newValue } }
    }

    public init(sources: [TrackKind: (primary: String, backups: [String])], mode: NodeMode, config: RipperConfig = RipperConfig(),
                transport: RangeTransport, auto: AutoConcurrency?, policy: MediaURLPolicy = .bilibili,
                clock: MonotonicClock = .system, logger: Logger = .shared) {
        let follower = config.fixedConcurrency == nil ? auto : nil
        let pool = ConnectionPool(limit: config.fixedConcurrency ?? follower?.threads ?? 16, clock: clock)
        ctx = EngineContext(transport: transport, pool: pool, config: config, meter: Meter(), stats: EngineStats(),
                            auto: follower, clock: clock, logger: logger)
        var resolvers: [TrackKind: Resolver] = [:]
        for (kind, source) in sources {
            resolvers[kind] = Resolver(primary: source.primary, backups: source.backups, mode: mode, policy: policy, bans: bans, clock: clock)
        }
        self.resolvers = resolvers
        downloader = RangeDownloader(ctx: ctx)
        bans.onBan = { node, strikes, kind in
            logger.warn(.engine, "ban", ["node": .init(node), "strikes": .init(strikes), "kind": .init(String(describing: kind))])
        }
        if let follower {
            pool.onChange = { active, limit, queued in follower.demand(active: active, limit: limit, queued: queued) }
            // The connection count is app-wide with one handler slot: the newest session takes it, and a
            // closed session's handler, until replaced, does nothing. Deliveries from different threads
            // can arrive out of order, so the limit is read from `threads`, not taken from the arguments.
            follower.onChange = { [weak self, weak follower] threads, previous, reason in
                guard let self, let follower, !self.isClosed else { return }
                self.ctx.pool.setLimit(follower.threads)
                logger.info(.engine, "threads", ["threads": .init(threads), "previous": .init(previous), "reason": .init(reason)])
            }
            follower.newSession()
            pool.setLimit(follower.threads)
        }
    }

    public func loadHeaders(_ track: TrackKind, through indexEnd: Int64) async throws -> TrackHeaders {
        guard !isClosed else { throw RipperError.closed }
        guard let resolver = resolvers[track], let range = ByteRange(start: 0, end: indexEnd) else { throw RipperError.noNodes }
        let output = try await downloader.meta(range, resolver: resolver)
        guard let total = output.total else { throw RipperError.badResponse(status: 206) }
        let headers = TrackHeaders(bytes: output.bytes, totalSize: total)
        state.withLock { $0.headers[track] = headers }
        ctx.logger.info(.engine, "headers", ["track": .init(track.rawValue), "bytes": .init(Int64(output.bytes.count)),
                                             "node": .init(NodeCatalog.nodeKey(of: output.url))])
        return headers
    }

    public func setSegments(_ track: TrackKind, _ segments: [MediaSegment]) {
        var positions: [Int64: Int] = [:]
        for (position, segment) in segments.enumerated() { positions[segment.range.start] = position }
        state.withLock { value in
            value.segments[track] = segments
            value.segmentAt[track] = positions
        }
    }

    public func read(_ track: TrackKind, _ range: ByteRange) -> AsyncThrowingStream<[UInt8], Error> {
        AsyncThrowingStream { continuation in
            // Created under the lock so `close()` sees every read, and the task cannot unregister
            // itself before it is registered.
            let task = state.withLock { value -> Task<Void, Never>? in
                guard !value.closed else { return nil }
                value.nextReadID += 1
                let id = value.nextReadID
                let task = Task {
                    do {
                        try await self.serve(track, range) { continuation.yield($0) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: self.isClosed ? RipperError.closed : error)
                    }
                    self.state.withLock { _ = $0.reads.removeValue(forKey: id) }
                }
                value.reads[id] = task
                return task
            }
            guard let task else {
                continuation.finish(throwing: RipperError.closed)
                return
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func updatePlayhead(seconds: Double, rate: Double) {
        playback.withLock { $0 = (seconds, rate > 0 ? rate : 1) }
        state.withLock { value in
            value.cache = value.cache.filter { $0.value.endTime >= seconds - 2 }
        }
    }

    public func reportBuffer(aheadSeconds: Double, playing: Bool) {
        ctx.auto?.buffer(ahead: aheadSeconds, playing: playing)
    }

    public func reportStall() {
        ctx.auto?.stall()
    }

    public func replaceURLs(_ track: TrackKind, primary: String, backups: [String]) {
        resolvers[track]?.replaceURLs(primary: primary, backups: backups)
        ctx.logger.info(.engine, "urls replaced", ["track": .init(track.rawValue), "url": .init(primary)])
    }

    /// The phone's network path changed: bans and backoffs from the old path are dropped, and with
    /// a different interface the speed measurements too.
    public func networkChanged(interfaceChanged: Bool) {
        bans.reset()
        for resolver in resolvers.values { resolver.resetHealth(clearMeasurements: interfaceChanged) }
        ctx.nodes.reset()
        ctx.logger.info(.engine, "network changed, node health reset", ["interfaceChanged": .init(interfaceChanged)])
    }

    /// Memory warning: drops cached and still-downloading prefetched segments; playback goes on.
    public func dropCache() {
        let tasks = state.withLock { value -> [Task<[UInt8], Error>] in
            value.cache.removeAll()
            defer { value.inflight.removeAll() }
            return Array(value.inflight.values)
        }
        tasks.forEach { $0.cancel() }
    }

    public func stats() -> RipperStats {
        var stats = ctx.stats.snapshot()
        stats.concurrency = ctx.pool.limit
        stats.nodeStates = resolvers[.video]?.status() ?? []
        return stats
    }

    public func close() {
        let (prefetches, reads) = state.withLock { value -> ([Task<[UInt8], Error>], [Task<Void, Never>]) in
            value.closed = true
            value.cache.removeAll()
            defer {
                value.inflight.removeAll()
                value.reads.removeAll()
            }
            return (Array(value.inflight.values), Array(value.reads.values))
        }
        ctx.pool.onChange = nil
        prefetches.forEach { $0.cancel() }
        reads.forEach { $0.cancel() }
    }

    private var isClosed: Bool { state.withLock { $0.closed } }

    private enum Plan {
        case memory([UInt8])
        case inflight(Task<[UInt8], Error>)
        case fetch
    }

    private struct Request {
        var plan: Plan
        var segment: MediaSegment?
        var number: UInt64 = 0
        var seek = false
        var firstOfTrack = false
        var total: Int64?
    }

    private func serve(_ track: TrackKind, _ range: ByteRange, emit: @escaping @Sendable ([UInt8]) -> Void) async throws {
        guard let resolver = resolvers[track] else { throw RipperError.noNodes }
        let began = ctx.clock.nowMs()
        let key = CacheKey(track: track, range: range)
        let request = try state.withLock { value -> Request in
            guard !value.closed else { throw RipperError.closed }
            if let headers = value.headers[track], range.end < Int64(headers.bytes.count) {
                return Request(plan: .memory(Array(headers.bytes[Int(range.start)...Int(range.end)])))
            }
            let positions = value.segmentAt[track]
            let segment = positions?[range.start].flatMap { value.segments[track]?[$0] }
            let previous = value.lastRequest[track]
            value.lastRequest[track] = range
            value.requests += 1
            var request = Request(plan: .fetch, segment: segment, number: value.requests,
                                  seek: Self.isSeek(range, previous: previous, positions: positions), firstOfTrack: previous == nil,
                                  total: value.headers[track]?.totalSize)
            if let entry = value.cache.removeValue(forKey: key) {
                request.plan = .memory(entry.bytes)
            } else if let task = value.inflight.removeValue(forKey: key) {
                // Taken out of `inflight`, so a seek cannot cancel it and its bytes do not also land in the cache.
                request.plan = .inflight(task)
            } else if request.seek {
                value.seeks += 1
            }
            if case .memory = request.plan {} else { value.playerPending[key, default: 0] += 1 }
            return request
        }
        defer {
            if case .memory = request.plan {} else {
                state.withLock { value in
                    let left = (value.playerPending[key] ?? 1) - 1
                    value.playerPending[key] = left > 0 ? left : nil
                }
            }
        }
        var served = false
        var source = "fetch"
        switch request.plan {
        case .memory(let bytes):
            ctx.stats.cache(hit: true)
            emit(bytes)
            served = true
            source = "memory"
        case .inflight(let task):
            let result = await withTaskCancellationHandler { await task.result } onCancel: { task.cancel() }
            try Task.checkCancellation()
            if case .success(let bytes) = result {
                ctx.stats.cache(hit: true)
                emit(bytes)
                served = true
                source = "prefetch"
            }
        case .fetch:
            break
        }
        if !served {
            ctx.stats.cache(hit: false)
            if case .fetch = request.plan, request.seek {
                dropPrefetch(track)
                if !request.firstOfTrack { ctx.auto?.newSession() }
            }
            do {
                for try await chunk in downloader.stream(range, resolver: resolver, startup: request.seek, priority: ctx.config.priority,
                                                         deadline: deadline(for: request.segment), expectedTotal: request.total) {
                    emit(chunk)
                }
                try Task.checkCancellation()
            } catch {
                if !Task.isCancelled && !(error is CancellationError) {
                    ctx.logger.error(.engine, "range failed", ["track": .init(track.rawValue), "range": .init(range.description),
                                                               "error": .init(String(describing: error))])
                    if claimFatal(request.number) { onFatal?(error) }
                }
                throw error
            }
        }
        ctx.logger.debug(.engine, "read", ["track": .init(track.rawValue), "range": .init(range.description), "source": .init(source),
                                           "seek": .init(request.seek), "ms": .init((ctx.clock.nowMs() - began).rounded())])
        schedulePrefetch(track, after: request.segment)
    }

    /// AVPlayer may ask for a track's next segment before the current one is in, and two such requests
    /// can arrive out of order, so a request within a segment (or, unaligned, its own length) of the
    /// previous one is not a seek.
    private static func isSeek(_ range: ByteRange, previous: ByteRange?, positions: [Int64: Int]?) -> Bool {
        guard let previous else { return true }
        if let position = positions?[range.start], let last = positions?[previous.start] {
            return position < last - 1 || position > last + 2
        }
        return range.start < previous.start - range.length || range.start > previous.end + 1 + range.length
    }

    private func claimFatal(_ number: UInt64) -> Bool {
        state.withLock { value in
            guard !value.closed, number > value.fatalCovered else { return false }
            value.fatalCovered = value.requests
            return true
        }
    }

    /// When playback needs this segment, as a monotonic time in ms; re-read on every queue pass.
    private func deadline(for segment: MediaSegment?) -> (@Sendable () -> Double)? {
        guard let segment else { return nil }
        let clock = ctx.clock
        let playback = self.playback
        return {
            let (playhead, rate) = playback.current
            return clock.nowMs() + max(0, segment.startTime - playhead) / rate * 1000
        }
    }

    /// After a seek the track's prefetched segments belong to the old position; left in place they
    /// would hold the cap and keep the new position from being prefetched.
    private func dropPrefetch(_ track: TrackKind) {
        let tasks = state.withLock { value -> [Task<[UInt8], Error>] in
            value.cache = value.cache.filter { $0.key.track != track }
            let keys = value.inflight.keys.filter { $0.track == track }
            return keys.compactMap { value.inflight.removeValue(forKey: $0) }
        }
        tasks.forEach { $0.cancel() }
    }

    private static func prefetchedBytes(_ value: State, _ track: TrackKind) -> Int64 {
        let cached = value.cache.filter { $0.key.track == track }.reduce(Int64(0)) { $0 + Int64($1.value.bytes.count) }
        let pending = value.inflight.keys.filter { $0.track == track }.reduce(Int64(0)) { $0 + $1.range.length }
        return cached + pending
    }

    private func schedulePrefetch(_ track: TrackKind, after segment: MediaSegment?) {
        guard let segment, let resolver = resolvers[track] else { return }
        let cap = track == .video ? ctx.config.prefetchVideoBytes : ctx.config.prefetchAudioBytes
        let aheadLimit = ctx.config.prefetchAheadSeconds
        let playhead = playback.current.seconds
        let downloader = self.downloader
        state.withLock { value in
            guard !value.closed, let segments = value.segments[track],
                  let position = value.segmentAt[track]?[segment.range.start] else { return }
            let total = value.headers[track]?.totalSize
            var budget = cap - Self.prefetchedBytes(value, track)
            for next in segments[(position + 1)...] {
                if next.startTime - playhead > aheadLimit { break }
                let key = CacheKey(track: track, range: next.range)
                if value.cache[key] != nil || value.inflight[key] != nil || value.playerPending[key] != nil { continue }
                if next.range.length > budget { break }
                budget -= next.range.length
                let deadline = deadline(for: next)
                let task = Task<[UInt8], Error> {
                    var bytes: [UInt8] = []
                    bytes.reserveCapacity(Int(next.range.length))
                    for try await chunk in downloader.stream(next.range, resolver: resolver, startup: false, priority: 10,
                                                             deadline: deadline, expectedTotal: total) {
                        bytes += chunk
                    }
                    try Task.checkCancellation()
                    return bytes
                }
                value.inflight[key] = task
                Task { [weak self] in
                    let result = await task.result
                    self?.prefetchFinished(key, task: task, result: result, endTime: next.endTime)
                }
            }
        }
    }

    private func prefetchFinished(_ key: CacheKey, task: Task<[UInt8], Error>, result: Result<[UInt8], Error>, endTime: Double) {
        state.withLock { value in
            guard value.inflight[key] == task else { return }
            value.inflight[key] = nil
            if case .success(let bytes) = result, !value.closed { value.cache[key] = CacheEntry(bytes: bytes, endTime: endTime) }
        }
        if case .failure(let error) = result, !(error is CancellationError) {
            ctx.logger.warn(.engine, "prefetch failed", ["track": .init(key.track.rawValue), "range": .init(key.range.description),
                                                         "error": .init(String(describing: error))])
        }
    }
}

/// For tests.
extension RipperSession {
    func isCached(_ track: TrackKind, _ range: ByteRange) -> Bool {
        state.withLock { $0.cache[CacheKey(track: track, range: range)] != nil }
    }
    var nodeStats: NodeStats { ctx.nodes }
    var seekCount: Int { state.withLock { $0.seeks } }
    var mediaRequestCount: Int { state.withLock { Int($0.requests) } }
    func prefetchedBytes(_ track: TrackKind) -> Int64 { state.withLock { Self.prefetchedBytes($0, track) } }
    func cachedBytes(_ track: TrackKind) -> Int64 {
        state.withLock { value in value.cache.filter { $0.key.track == track }.reduce(Int64(0)) { $0 + Int64($1.value.bytes.count) } }
    }
    func prefetchesRunning(_ track: TrackKind) -> Int { state.withLock { value in value.inflight.keys.filter { $0.track == track }.count } }
}
