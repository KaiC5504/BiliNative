import Foundation
import BiliShared

enum PieceMode: Sendable {
    case normal
    /// The first segment of a playback or after a seek.
    case startup
    /// The first small piece of a startup range, raced over many nodes at once.
    case probe

    var queueClass: QueueClass {
        switch self {
        case .probe: return .critical
        case .startup: return .startup
        case .normal: return .ordinary
        }
    }
}

extension EngineContext {
    /// BTR's pause before retry round `round` (1 or later): 0.5 s, 1 s, at most 2 s. False once
    /// the retry window that began at `startedAt` is spent.
    func pauseBeforeRound(_ round: Int, startedAt: Double) async throws -> Bool {
        if clock.nowMs() - startedAt > config.retryWindowMs { return false }
        try await sleepMs(min(2_000, 500 * pow(2, Double(round - 1))))
        return true
    }
}

/// The first copy to succeed wins and the others are cancelled; when every copy fails, the last error.
func firstSuccess<Output: Sendable>(_ group: inout ThrowingTaskGroup<Output, Error>) async throws -> Output {
    var lastError: Error = RipperError.noNodes
    while true {
        do {
            guard let output = try await group.next() else { break }
            group.cancelAll()
            return output
        } catch {
            lastError = error
        }
    }
    throw lastError
}

final class PieceDownloader: @unchecked Sendable {
    static let resumeMinBytes: Int64 = 32 * 1024

    let ctx: EngineContext
    let runner: AttemptRunner

    init(ctx: EngineContext) {
        self.ctx = ctx
        runner = AttemptRunner(ctx: ctx)
    }

    /// One piece, in up to `pieceRounds` rounds. Each round walks the candidates two at a time: the
    /// first copy starts at once, the backup copy once the first is late (see `hedgeDue`); the first
    /// to finish wins and the other is cancelled. Bytes already received survive into the next try.
    func download(piece: ByteRange, index: Int, resolver: Resolver, preferred: [String], mode: PieceMode, priority: Double,
                  deadline: (@Sendable () -> Double)?) async throws -> AttemptOutput {
        let started = ctx.clock.nowMs()
        let prefix = Locked(Prefix())
        var lastError: Error = RipperError.noNodes
        for round in 0..<ctx.config.pieceRounds {
            if round > 0 {
                guard try await ctx.pauseBeforeRound(round, startedAt: started) else { break }
            }
            let candidates = Self.candidates(preferred: preferred, resolver: resolver, pieceIndex: index, round: round)
            let limit = min(8, candidates.count)
            let width = mode == .probe ? limit : 2
            var tried = Set<String>()
            while tried.count < limit {
                try Task.checkCancellation()
                let untried = candidates.filter { !tried.contains($0) }
                let open = untried.filter(resolver.allows)
                let pair = Array((open.isEmpty ? untried : open).prefix(width))
                if pair.isEmpty { break }
                pair.forEach { tried.insert($0) }
                do {
                    let output = try await race(pair, piece: piece, resolver: resolver, mode: mode, priority: priority,
                                                deadline: deadline, prefix: prefix)
                    ctx.auto?.delivered(piece.length)
                    ctx.stats.delivered(piece.length)
                    return output
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    lastError = error
                }
            }
        }
        throw lastError
    }

    private func race(_ pair: [String], piece: ByteRange, resolver: Resolver, mode: PieceMode, priority: Double,
                      deadline: (@Sendable () -> Double)?, prefix: Locked<Prefix>) async throws -> AttemptOutput {
        let first = AttemptProgress()
        let hasDeadline = deadline.map { $0().isFinite } ?? false
        return try await withThrowingTaskGroup(of: AttemptOutput.self) { group -> AttemptOutput in
            for (position, url) in pair.enumerated() {
                group.addTask {
                    let progress = position == 0 ? first : AttemptProgress()
                    if position > 0 {
                        try await self.waitForCopy(first: first, copyURL: url, resolver: resolver, mode: mode,
                                                   hasDeadline: hasDeadline, deadline: deadline)
                    }
                    do {
                        return try await self.runner.run(
                            url: url, piece: piece, progress: progress, resolver: resolver,
                            priority: priority + (position > 0 ? 20 : 0), queueClass: mode.queueClass, deadline: deadline,
                            resumeBase: { Self.resumeBase(prefix: prefix.current, live: position > 0 ? first.prefix() : nil, pieceLength: piece.length) })
                    } catch {
                        let kept = progress.prefix()
                        if kept.bytes < piece.length {
                            prefix.withLock { if kept.bytes > $0.bytes { $0 = kept } }
                        }
                        if position == 0 { first.markFailed() }
                        throw error
                    }
                }
            }
            return try await firstSuccess(&group)
        }
    }

    static func resumeBase(prefix: Prefix, live: Prefix?, pieceLength: Int64) -> Prefix {
        var base = prefix.bytes >= resumeMinBytes ? prefix : Prefix()
        if let live, live.bytes >= resumeMinBytes, live.bytes > base.bytes { base = live }
        return base.bytes >= pieceLength ? Prefix() : base
    }

    private func waitForCopy(first: AttemptProgress, copyURL: String, resolver: Resolver, mode: PieceMode,
                             hasDeadline: Bool, deadline: (@Sendable () -> Double)?) async throws {
        if mode == .probe { return }
        let measured = ctx.meter.hedgeDelayMs(configured: ctx.config.hedgeDelayMs)
        let delay = mode == .startup ? min(hasDeadline ? 200 : 250, measured) : measured
        let waitStarted = ctx.clock.nowMs()
        while true {
            if first.failed { return }
            if hasDeadline, let deadline {
                if first.isStarted && hedgeDue(first: first, delayMs: delay, deadlineAt: deadline(), copyBps: resolver.speed(copyURL)) { return }
            } else if ctx.clock.nowMs() - waitStarted >= delay {
                return
            }
            try await sleepMs(50)
        }
    }

    /// BTR `hedgeDue`, without the rescue budgets.
    func hedgeDue(first: AttemptProgress, delayMs: Double, deadlineAt: Double, copyBps: Double) -> Bool {
        let now = ctx.clock.nowMs()
        let usual = ctx.meter.connectionBps
        return first.state.withLock { value in
            let ran = now - value.startedAt
            if value.received != value.seenBytes {
                value.seenBytes = value.received
                value.seenAt = now
            }
            if ran < delayMs { return false }
            if value.received == 0 || now - value.seenAt >= delayMs { return true }
            let rate = Double(value.received) * 1000 / ran
            let remaining = Double(max(0, value.length - value.received))
            if now + remaining * 1000 / rate <= deadlineAt - 1_500 { return false }
            if copyBps > rate * 1.5 { return true }
            if !(usual > 0) || rate < usual * 0.6 { return true }
            return !(copyBps > 0)
        }
    }

    /// BTR `pieceCandidates`: the assigned node first, then the fastest known nodes.
    static func candidates(preferred: [String], resolver: Resolver, pieceIndex: Int, round: Int) -> [String] {
        let offset = preferred.isEmpty ? 0 : round % preferred.count
        let rotated = Array(preferred[offset...] + preferred[..<offset])
        let rescue = resolver.rescueCandidates().filter { !rotated.contains($0) }
        let rest = (Array(rotated.dropFirst()) + rescue).sorted { resolver.speed($0) > resolver.speed($1) }
        var list = rotated.isEmpty ? rest : [rotated[0]] + rest
        for url in resolver.ordered(pieceIndex: pieceIndex) where !list.contains(url) {
            list.append(url)
        }
        return list
    }
}
