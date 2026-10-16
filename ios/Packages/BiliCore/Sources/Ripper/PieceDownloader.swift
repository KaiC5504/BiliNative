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

/// Where the copies of one race go. A copy takes its node once it holds a connection permit: the first candidate no
/// other copy took that has room, or the first one left when every node is full. On the phone (2026-10-17) Akamai,
/// fastest and HTTP/1.1, was given 48-61 requests for its 8 connections while the mirrors sat idle, and 38 of them
/// ran out their first-byte timeout waiting inside URLSession.
final class CopyTargets: @unchecked Sendable {
    let candidates: [String]
    private let nodes: NodeStats
    private let taken = Locked<[Int: String]>([:])

    init(_ candidates: [String], nodes: NodeStats) {
        self.candidates = candidates
        self.nodes = nodes
    }

    func url(_ copy: Int) -> String? { taken.current[copy] }

    /// Where the next copy would go now.
    func next() -> String {
        let left = remaining(taken.current)
        return left.first { !nodes.isFull($0) } ?? left.first ?? candidates[0]
    }

    func claim(_ copy: Int) -> String {
        taken.withLock { taken in
            let left = remaining(taken)
            let url = nodes.begin(firstOpenOf: left.isEmpty ? candidates : left)
            taken[copy] = url
            return url
        }
    }

    private func remaining(_ taken: [Int: String]) -> [String] {
        candidates.filter { !taken.values.contains($0) }
    }
}

final class PieceDownloader: @unchecked Sendable {
    static let resumeMinBytes: Int64 = 32 * 1024

    let ctx: EngineContext
    let runner: AttemptRunner

    init(ctx: EngineContext) {
        self.ctx = ctx
        runner = AttemptRunner(ctx: ctx)
    }

    /// One piece, in up to `pieceRounds` rounds. Each round walks the candidates three at a time: the
    /// first copy starts at once, the backup copy once the first is late (see `hedgeDue`), and in a hurry
    /// a third once the backup is late too (see `hurryHedgeDue`); the first to finish wins and the others
    /// are cancelled. A copy skips a full node while another has room (`CopyTargets`). Bytes already
    /// received survive into the next try.
    func download(piece: ByteRange, index: Int, resolver: Resolver, preferred: [String], mode: PieceMode, priority: Double,
                  deadline: (@Sendable () -> Double)?, hurry: (@Sendable () -> Bool)? = nil) async throws -> AttemptOutput {
        let started = ctx.clock.nowMs()
        let prefix = Locked(Prefix())
        var lastError: Error = RipperError.noNodes
        for round in 0..<ctx.config.pieceRounds {
            if round > 0 {
                guard try await ctx.pauseBeforeRound(round, startedAt: started) else { break }
            }
            let candidates = Self.candidates(preferred: preferred, resolver: resolver, pieceIndex: index, round: round)
            let limit = min(8, candidates.count)
            let width = mode == .probe ? limit : 3
            var tried = Set<String>()
            while tried.count < limit {
                try Task.checkCancellation()
                let untried = candidates.filter { !tried.contains($0) }
                let allowed = untried.filter(resolver.allows)
                let whole = allowed.filter { !resolver.avoids($0, piece) }
                let targets = CopyTargets(!whole.isEmpty ? whole : !allowed.isEmpty ? allowed : untried, nodes: ctx.nodes)
                if targets.candidates.isEmpty { break }
                let copies = targets.candidates.prefix(width).map { _ in AttemptProgress() }
                do {
                    let output = try await race(targets, copies: copies, piece: piece, resolver: resolver, mode: mode, priority: priority,
                                                deadline: deadline, hurry: hurry, prefix: prefix)
                    ctx.auto?.delivered(piece.length)
                    ctx.stats.delivered(piece.length)
                    return output
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    lastError = error
                }
                // A copy that never sent its request leaves its node to a later group of this round.
                let used = copies.indices.compactMap { copies[$0].isStarted ? targets.url($0) : nil }
                tried.formUnion(used.isEmpty ? [targets.candidates[0]] : used)
            }
        }
        throw lastError
    }

    /// Copy k waits on copy k - 1; a copy that is never needed returns nil without sending a request.
    private func race(_ targets: CopyTargets, copies: [AttemptProgress], piece: ByteRange, resolver: Resolver, mode: PieceMode, priority: Double,
                      deadline: (@Sendable () -> Double)?, hurry: (@Sendable () -> Bool)?, prefix: Locked<Prefix>) async throws -> AttemptOutput {
        let hasDeadline = deadline.map { $0().isFinite } ?? false
        return try await withThrowingTaskGroup(of: AttemptOutput?.self) { group -> AttemptOutput in
            for position in copies.indices {
                group.addTask {
                    let progress = copies[position]
                    if position > 0 {
                        guard try await self.waitForCopy(position, previous: copies[position - 1],
                                                         previousURL: { targets.url(position - 1) ?? targets.candidates[0] },
                                                         copyURL: targets.next, pieceLength: piece.length, resolver: resolver, mode: mode,
                                                         hasDeadline: hasDeadline, deadline: deadline, hurry: hurry) else { return nil }
                    }
                    do {
                        return try await self.runner.run(
                            claim: { targets.claim(position) }, piece: piece, progress: progress, resolver: resolver,
                            priority: priority + (position > 0 ? 20 : 0), queueClass: mode.queueClass, deadline: deadline,
                            copy: mode == .probe ? 1 : position + 1, resumeBase: {
                                let live = copies[..<position].map { $0.prefix() }.max { $0.bytes < $1.bytes }
                                return Self.resumeBase(prefix: prefix.current, live: live, pieceLength: piece.length)
                            })
                    } catch {
                        let kept = progress.prefix()
                        if kept.bytes < piece.length {
                            prefix.withLock { if kept.bytes > $0.bytes { $0 = kept } }
                        }
                        progress.markFailed()
                        throw error
                    }
                }
            }
            var lastError: Error = RipperError.noNodes
            while true {
                do {
                    guard let result = try await group.next() else { break }
                    if let output = result {
                        copies.forEach { $0.markOutrun() }
                        group.cancelAll()
                        return output
                    }
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
    }

    static func resumeBase(prefix: Prefix, live: Prefix?, pieceLength: Int64) -> Prefix {
        var base = prefix.bytes >= resumeMinBytes ? prefix : Prefix()
        if let live, live.bytes >= resumeMinBytes, live.bytes > base.bytes { base = live }
        return base.bytes >= pieceLength ? Prefix() : base
    }

    /// Whether copy `position` sends its request. In a hurry it goes once the copy before it is late or has
    /// failed. Otherwise the second copy follows `hedgeDue` or the delay, and a third waits for a hurry: when
    /// the second fails first, the round's walk moves on instead.
    private func waitForCopy(_ position: Int, previous: AttemptProgress, previousURL: () -> String, copyURL: () -> String, pieceLength: Int64,
                             resolver: Resolver, mode: PieceMode, hasDeadline: Bool, deadline: (@Sendable () -> Double)?,
                             hurry: (@Sendable () -> Bool)?) async throws -> Bool {
        if mode == .probe { return true }
        let measured = ctx.meter.hedgeDelayMs(configured: ctx.config.hedgeDelayMs)
        let delay = mode == .startup ? min(hasDeadline ? 200 : 250, measured) : measured
        let waitStarted = ctx.clock.nowMs()
        while true {
            let hurried = hurry?() == true
            if previous.failed { return hurried || position == 1 }
            if hurried {
                if previous.isStarted && hurryHedgeDue(previous: previous, url: previousURL(), pieceLength: pieceLength) { return true }
            } else if position == 1 {
                if hasDeadline, let deadline {
                    if previous.isStarted && hedgeDue(first: previous, delayMs: delay, deadlineAt: deadline(), copyBps: resolver.speed(copyURL())) {
                        return true
                    }
                } else if ctx.clock.nowMs() - waitStarted >= delay {
                    return true
                }
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

    /// BTR PR 11 `overdue` with little buffered: a second copy costs less than the wait, since a node can take
    /// seconds over a part of the file it has not served lately. Due when the copy before is late to its first
    /// byte (twice its node's usual, within 250-600 ms), has stopped for 1 s, or is past twice its node's
    /// expected time with under three quarters in.
    func hurryHedgeDue(previous: AttemptProgress, url: String, pieceLength: Int64) -> Bool {
        let now = ctx.clock.nowMs()
        let ttfb = ctx.nodes.ttfbMs(url)
        let expected = ctx.nodes.expectedMs(url, pieceBytes: pieceLength) ?? ctx.config.hedgeDelayMs
        return previous.state.withLock { value in
            let elapsed = now - value.startedAt
            if !value.gotHeaders { return elapsed >= (ttfb > 0 ? min(600, max(250, ttfb * 2)) : 250) }
            if now - value.lastProgressAt >= 1_000 { return true }
            let arrived = Double(value.base.bytes + value.received)
            return elapsed >= max(400, expected * 2) && arrived < Double(pieceLength) * 0.75
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
