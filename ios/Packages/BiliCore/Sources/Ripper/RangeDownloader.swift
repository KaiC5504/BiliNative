import Foundation
import BiliShared

final class RangeDownloader: @unchecked Sendable {
    let ctx: EngineContext
    let pieces: PieceDownloader
    let assigner = PrimaryAssigner()

    init(ctx: EngineContext) {
        self.ctx = ctx
        pieces = PieceDownloader(ctx: ctx)
    }

    /// BTR `downloadStartupRange`: init and index in one request, raced over up to three nodes
    /// started 0, 120 and 300 ms apart; rounds as for pieces.
    func meta(_ range: ByteRange, resolver: Resolver) async throws -> AttemptOutput {
        let started = ctx.clock.nowMs()
        var lastError: Error = RipperError.noNodes
        for round in 0..<ctx.config.pieceRounds {
            if round > 0 {
                guard try await ctx.pauseBeforeRound(round, startedAt: started) else { break }
            }
            var candidates = Array(resolver.startupCandidates().prefix(3))
            if candidates.isEmpty && round > 0 { candidates = Array(resolver.ordered(pieceIndex: round).prefix(3)) }
            if candidates.isEmpty { break }
            do {
                return try await withThrowingTaskGroup(of: AttemptOutput.self) { group -> AttemptOutput in
                    let delays: [Double] = [0, 120, 300]
                    for (index, url) in candidates.enumerated() {
                        group.addTask {
                            try await sleepMs(delays[index])
                            return try await self.pieces.runner.run(url: url, piece: range, progress: AttemptProgress(), resolver: resolver,
                                                                    priority: 220, queueClass: .critical, deadline: nil, resumeBase: { Prefix() })
                        }
                    }
                    return try await firstSuccess(&group)
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }

    /// The bytes of `range` in file order, each piece yielded as soon as it and all before it are in.
    /// Every piece's advertised file size must equal `expectedTotal` (when given) and each other's;
    /// a piece that disagrees fails the range before any of its bytes are yielded.
    func stream(_ range: ByteRange, resolver: Resolver, startup: Bool, priority: Double,
                deadline: (@Sendable () -> Double)?, expectedTotal: Int64? = nil) -> AsyncThrowingStream<[UInt8], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(range, resolver: resolver, startup: startup, priority: priority, deadline: deadline,
                                       expectedTotal: expectedTotal) {
                        continuation.yield($0)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ range: ByteRange, resolver: Resolver, startup: Bool, priority: Double,
                     deadline: (@Sendable () -> Double)?, expectedTotal: Int64?, emit: @escaping @Sendable ([UInt8]) -> Void) async throws {
        var knownTotal = expectedTotal
        func check(_ output: AttemptOutput) throws {
            guard let total = output.total else { return }
            if let knownTotal, knownTotal != total { throw RipperError.totalMismatch }
            knownTotal = total
        }
        var preferred = resolver.rangeCandidates()
        var assignable = preferred
        var remaining = range
        var indexOffset = 0
        if startup {
            // A small head piece raced over every candidate measures the nodes and gets the first bytes
            // to the player fast; the rest is then spread over the nodes that proved themselves.
            let headLength = min(range.length, max(64 * 1024, ctx.config.minChunkBytes))
            guard let head = ByteRange(start: range.start, end: range.start + headLength - 1) else { return }
            let result = try await pieces.download(piece: head, index: 0, resolver: resolver, preferred: preferred, mode: .probe,
                                                   priority: 220, deadline: deadline)
            try check(result)
            emit(result.bytes)
            guard head.end < range.end, let rest = ByteRange(start: head.end + 1, end: range.end) else { return }
            remaining = rest
            preferred = [result.url] + preferred.filter { $0 != result.url }
            assignable = preferred.filter { $0 == result.url || resolver.speed($0) > 0 }
            indexOffset = 1
        }
        let concurrency = ctx.pool.limit
        let rescueReserve = concurrency >= 8 ? min(8, max(1, (concurrency + 7) / 8)) : 0
        let pieceConcurrency = max(1, concurrency - rescueReserve)
        let minChunk = ctx.meter.adaptiveMinChunk(base: ctx.config.minChunkBytes, rangeLength: remaining.length,
                                                  pieceLimit: pieceConcurrency, hostCount: preferred.count)
        let parts = remaining.split(concurrency: pieceConcurrency, minChunk: minChunk)
        let primaries = assigner.assign(urls: assignable, count: parts.count, speed: resolver.speed, trialKey: ObjectIdentifier(resolver))
        let mode: PieceMode = startup ? .startup : .normal
        let order = preferred
        try await withThrowingTaskGroup(of: (Int, AttemptOutput).self) { group in
            for (offset, part) in parts.enumerated() {
                let primary = offset < primaries.count ? primaries[offset] : order.first
                let piecePreferred = primary.map { first in [first] + order.filter { $0 != first } } ?? order
                let pieceIndex = offset + indexOffset
                let piecePriority = startup ? 120 - Double(min(30, pieceIndex)) : priority - Double(min(20, pieceIndex))
                group.addTask {
                    let output = try await self.pieces.download(piece: part, index: pieceIndex, resolver: resolver, preferred: piecePreferred,
                                                                mode: mode, priority: piecePriority, deadline: deadline)
                    return (offset, output)
                }
            }
            var ready: [Int: AttemptOutput] = [:]
            var next = 0
            for try await (offset, output) in group {
                try check(output)
                ready[offset] = output
                while let item = ready.removeValue(forKey: next) {
                    emit(item.bytes)
                    next += 1
                }
            }
        }
    }
}
