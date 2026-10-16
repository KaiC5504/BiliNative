import Foundation
import BiliShared
import DevLog

struct EngineContext: @unchecked Sendable {
    let transport: RangeTransport
    let pool: ConnectionPool
    let config: RipperConfig
    let meter: Meter
    let stats: EngineStats
    let auto: AutoConcurrency?
    let clock: MonotonicClock
    let logger: Logger
    /// A class, so copies of the context share one record.
    var nodes = NodeStats()
}

/// Bytes already held from the front of a piece; a retry or a backup copy asks only for the rest.
struct Prefix: Sendable {
    var bytes: Int64 = 0
    var chunks: [[UInt8]] = []
}

struct AttemptOutput: Sendable {
    let bytes: [UInt8]
    let total: Int64?
    let url: String
}

/// Live state of one copy of a piece, read by the watchdog and by hedging decisions.
final class AttemptProgress: @unchecked Sendable {
    struct State {
        var started = false
        var startedAt: Double = 0
        var gotHeaders = false
        var headersAt: Double = 0
        var lastProgressAt: Double = 0
        var base = Prefix()
        var received: Int64 = 0
        var chunks: [[UInt8]] = []
        var length: Int64 = 0
        var seenBytes: Int64 = 0
        var seenAt: Double = 0
        var failed = false
    }

    let state = Locked(State())

    func begin(at: Double, length: Int64, base: Prefix) {
        state.withLock { value in
            value.started = true
            value.startedAt = at
            value.lastProgressAt = at
            value.seenAt = at
            value.length = length
            value.base = base
        }
    }

    func headers(at: Double) {
        state.withLock { value in
            value.gotHeaders = true
            value.headersAt = at
            value.lastProgressAt = at
        }
    }

    func append(_ chunk: [UInt8], at: Double) {
        state.withLock { value in
            value.received += Int64(chunk.count)
            value.chunks.append(chunk)
            value.lastProgressAt = at
        }
    }

    func markFailed() { state.withLock { $0.failed = true } }
    var failed: Bool { state.withLock { $0.failed } }
    var isStarted: Bool { state.withLock { $0.started } }
    var received: Int64 { state.withLock { $0.received } }
    var headersAt: Double { state.withLock { $0.headersAt } }
    var timing: (gotHeaders: Bool, lastProgressAt: Double) { state.withLock { ($0.gotHeaders, $0.lastProgressAt) } }

    /// The resumed base plus this copy's bytes: the front of the piece this copy has made available.
    func prefix() -> Prefix {
        state.withLock { Prefix(bytes: $0.base.bytes + $0.received, chunks: $0.base.chunks + $0.chunks) }
    }
}

struct AttemptRunner: Sendable {
    let ctx: EngineContext

    /// One request for `piece` (or its missing tail) to `url`: waits for a connection, enforces
    /// BTR's three timeouts, checks the 206 Content-Range and the length, and reports the outcome to
    /// the resolver, meter, stats and automatic connection count.
    func run(url: String, piece: ByteRange, progress: AttemptProgress, resolver: Resolver, priority: Double,
             queueClass: QueueClass, deadline: (@Sendable () -> Double)?, resumeBase: @Sendable () -> Prefix) async throws -> AttemptOutput {
        let permit = try await ctx.pool.acquire(priority: priority, queueClass: queueClass, deadline: deadline)
        defer { permit.release() }
        try Task.checkCancellation()
        // Taken now, not when queued: a backup copy that waited resumes from what the first copy has by now.
        var base = resumeBase()
        if base.bytes >= piece.length { base = Prefix() }
        guard let part = ByteRange(start: piece.start + base.bytes, end: piece.end) else { throw RipperError.invalidURL }
        let started = ctx.clock.nowMs()
        progress.begin(at: started, length: part.length, base: base)
        let node = NodeCatalog.nodeKey(of: url)
        ctx.stats.started(node: node)
        ctx.nodes.begin(url)
        defer { ctx.nodes.end(url, receiving: progress.timing.gotHeaders) }
        do {
            let output = try await withThrowingTaskGroup(of: AttemptOutput?.self) { group -> AttemptOutput in
                group.addTask { try await self.transfer(url: url, part: part, base: base, progress: progress, started: started, node: node) }
                group.addTask {
                    try await self.watchdog(progress: progress, started: started)
                    return nil
                }
                while let result = try await group.next() {
                    if let output = result {
                        group.cancelAll()
                        return output
                    }
                }
                throw RipperError.closed
            }
            let elapsed = max(1, ctx.clock.nowMs() - started)
            ctx.meter.record(bytes: part.length, elapsedMs: elapsed)
            ctx.nodes.body(url, bytes: part.length, ms: ctx.clock.nowMs() - progress.headersAt)
            resolver.success(url, bps: part.length >= Meter.sampleMinBytes ? Double(part.length) * 1000 / elapsed : 0)
            ctx.logger.debug(.engine, "piece", ["node": .init(node), "range": .init(part.description),
                                                "firstByteMs": .init((progress.headersAt - started).rounded()),
                                                "bytes": .init(part.length), "ms": .init(elapsed.rounded()), "resumed": .init(base.bytes)])
            return output
        } catch {
            let received = progress.received
            let elapsed = max(1, ctx.clock.nowMs() - started)
            let cancelled = Task.isCancelled || error is CancellationError
            let gotHeaders = progress.timing.gotHeaders
            if cancelled {
                if gotHeaders {
                    ctx.nodes.crawl(url, bytes: received, ms: ctx.clock.nowMs() - progress.headersAt)
                } else {
                    ctx.nodes.outrun(url, waitedMs: elapsed)
                }
                // A copy that lost the race still measured its node; without this a slow node is never measured.
                if received >= Meter.sampleMinBytes { resolver.sample(url, bps: Double(received) * 1000 / elapsed) }
                if received > 0 { resolver.streamed(url) }
                ctx.logger.debug(.engine, "attempt cancelled", ["node": .init(node), "range": .init(part.description),
                                                                "bytes": .init(received), "ms": .init(elapsed.rounded())])
            } else {
                let ripperError = error as? RipperError
                if ripperError == .firstByteTimeout { ctx.nodes.silent(url, waitedMs: elapsed) }
                resolver.failure(url, status: ripperError?.status, receivedBytes: received, range: part,
                                 timedOut: ripperError?.isTimeout == true)
                if let status = ripperError?.status, status == 412 || status == 429 {
                    ctx.auto?.pushback(status: status)
                } else if ripperError?.isTimeout == true && received == 0 {
                    ctx.auto?.slow()
                }
                ctx.logger.debug(.engine, "attempt failed", ["node": .init(node), "range": .init(part.description),
                                                             "error": .init(String(describing: error)),
                                                             "bytes": .init(received), "ms": .init(elapsed.rounded())])
            }
            ctx.stats.failed(node: node, wastedBytes: received, cancelled: cancelled)
            throw error
        }
    }

    private func transfer(url: String, part: ByteRange, base: Prefix, progress: AttemptProgress, started: Double, node: String) async throws -> AttemptOutput? {
        guard let target = URL(string: url) else { throw RipperError.invalidURL }
        let response = try await ctx.transport.fetch(target, range: part)
        let now = ctx.clock.nowMs()
        progress.headers(at: now)
        ctx.stats.firstByte(node: node, ms: now - started)
        ctx.nodes.firstByte(url, ms: now - started)
        let contentRange = ContentRange.parse(response.headers["content-range"])
        guard response.status == 206, let contentRange, contentRange.range == part else {
            throw RipperError.badResponse(status: response.status)
        }
        for try await chunk in response.body {
            try Task.checkCancellation()
            progress.append(chunk, at: ctx.clock.nowMs())
            ctx.auto?.activity()
        }
        // A cancelled body simply ends; that is not a short response.
        try Task.checkCancellation()
        let got = progress.received
        guard got == part.length else { throw RipperError.lengthMismatch(got: got, expected: part.length) }
        let whole = progress.prefix()
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Int(whole.bytes))
        for chunk in whole.chunks { bytes += chunk }
        return AttemptOutput(bytes: bytes, total: contentRange.total, url: url)
    }

    private func watchdog(progress: AttemptProgress, started: Double) async throws {
        while true {
            try await sleepMs(25)
            let timing = progress.timing
            let now = ctx.clock.nowMs()
            if !timing.gotHeaders && now - started > ctx.config.firstByteTimeoutMs { throw RipperError.firstByteTimeout }
            if timing.gotHeaders && now - timing.lastProgressAt > ctx.config.stallTimeoutMs { throw RipperError.stalled }
            if now - started > ctx.config.attemptTimeoutMs { throw RipperError.attemptTimeout }
        }
    }
}
