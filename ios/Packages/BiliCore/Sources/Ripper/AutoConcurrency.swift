import BiliShared

/// BTR `createAutoConcurrency`. The connection count climbs a ladder whenever downloading is not
/// keeping up (a stall, a low buffer that stops growing while bytes arrive, connections queueing
/// too long). Every step up is a trial: if throughput has not grown ten seconds later it is taken
/// back and that level rests. 412/429 step down and block the level for three minutes. Each new
/// playback starts with at least 16 connections and comes back down once the buffer is ahead.
public final class AutoConcurrency: @unchecked Sendable {
    public static let ladder = [8, 12, 16, 24, 32, 48, 64]
    static let startupLevel = 2
    static let startupComfortSeconds = 15.0
    static let startupMaxMs = 30_000.0
    static let stepCooldownMs = 2_500.0
    static let trialMs = 10_000.0
    static let windowMs = 5_000.0
    static let bucketMs = 250.0
    static let restMs = 90_000.0
    static let pushbackRestMs = 180_000.0
    static let lowBufferSeconds = 6.0
    static let pressureMs = 1_000.0
    static let activityMs = 1_500.0

    public struct Status: Equatable, Sendable {
        public let threads: Int
        public let reason: String
        public let throughputBps: Double
        public let saturation: Double
        public let inStartup: Bool
    }

    struct Trial { var from: Int; var level: Int; var at: Double; var baseline: Double; var stalled: Bool }
    struct Rest { var until: Double; var hard: Bool }
    struct Bucket { var at: Double; var bytes: Double }
    struct Span { var from: Double; var to: Double }
    struct Startup { var base: Int; var until: Double }

    struct State {
        var level = 0
        var changedAt = 0.0
        var reason = "起步"
        var steps = 0
        var trial: Trial?
        var resting: [Int: Rest] = [:]
        var buckets: [Bucket] = []
        var lastActivityAt = -Double.infinity
        var saturated = false
        var saturatedSince = 0.0
        var saturatedSpans: [Span] = []
        var aheadSamples: [(at: Double, ahead: Double)] = []
        var pressureSince = 0.0
        var startup: Startup?
    }

    typealias Change = (threads: Int, previous: Int, reason: String)
    public typealias ChangeHandler = (_ threads: Int, _ previous: Int, _ reason: String) -> Void

    private let state = Locked(State())
    private let handler = Locked<ChangeHandler?>(nil)
    private let clock: MonotonicClock

    /// Called outside the lock, once per step. Steps made by one call arrive in order; calls from
    /// different threads may deliver out of order, so read `threads` for the current value.
    public var onChange: ChangeHandler? {
        get { handler.current }
        set { handler.withLock { $0 = newValue } }
    }

    public init(clock: MonotonicClock = .system) {
        self.clock = clock
    }

    public var threads: Int { Self.ladder[state.current.level] }

    public func status() -> Status {
        mutate { value, at, _ in
            Status(threads: Self.ladder[value.level], reason: value.reason, throughputBps: Self.throughput(&value, at),
                   saturation: Self.saturation(&value, at), inStartup: value.startup != nil)
        }
    }

    /// A piece arrived whole. Hedge copies that lost are not delivery.
    public func delivered(_ bytes: Int64) {
        mutate { value, at, changes in
            if let last = value.buckets.last, at - last.at < Self.bucketMs {
                value.buckets[value.buckets.count - 1].bytes += Double(bytes)
            } else {
                value.buckets.append(Bucket(at: at, bytes: Double(bytes)))
            }
            Self.pruneBuckets(&value, at)
            Self.judgeTrial(&value, at, &changes)
        }
    }

    public func activity() {
        mutate { value, at, _ in value.lastActivityAt = at }
    }

    public func demand(active: Int, limit: Int, queued: Int) {
        mutate { value, at, _ in
            let saturated = active >= limit && queued > 0
            guard saturated != value.saturated else { return }
            if value.saturated { value.saturatedSpans.append(Span(from: value.saturatedSince, to: at)) }
            value.saturated = saturated
            value.saturatedSince = at
            _ = Self.saturation(&value, at)
        }
    }

    @discardableResult
    public func stall(_ reason: String = "播放卡了一下") -> Bool {
        mutate { value, at, changes in
            value.trial?.stalled = true
            return Self.stepUp(&value, reason, strong: true, at, &changes)
        }
    }

    /// The buffer ahead of the playhead, a few times a second while playing.
    @discardableResult
    public func buffer(ahead: Double, playing: Bool) -> Bool {
        mutate { value, at, changes in
            value.aheadSamples.append((at, ahead))
            while let first = value.aheadSamples.first, at - first.at > Self.pressureMs + Self.bucketMs {
                value.aheadSamples.removeFirst()
            }
            if let start = value.startup {
                if at >= start.until {
                    value.startup = nil
                } else if ahead >= Self.startupComfortSeconds && at - value.changedAt >= Self.stepCooldownMs {
                    if value.level > start.base {
                        Self.setLevel(&value, value.level - 1, "开头已经跟上，线程数降到 \(Self.ladder[value.level - 1])", nil, at, &changes)
                    }
                    if value.level <= start.base { value.startup = nil }
                }
            }
            let earlier = value.aheadSamples.first { at - $0.at >= Self.pressureMs }
            let downloading = at - value.lastActivityAt < Self.activityMs
            let pressed = playing && downloading && ahead < Self.lowBufferSeconds && earlier.map { ahead <= $0.ahead + 0.05 } == true
            if !pressed {
                value.pressureSince = 0
                return false
            }
            if value.pressureSince == 0 {
                value.pressureSince = at
                return false
            }
            if at - value.pressureSince < Self.pressureMs { return false }
            value.pressureSince = 0
            return Self.stepUp(&value, "缓冲跟不上播放", strong: false, at, &changes)
        }
    }

    /// A connection waited too long for its first byte while every slot was busy.
    @discardableResult
    public func slow() -> Bool {
        mutate { value, at, changes in
            Self.saturation(&value, at) >= 0.6 ? Self.stepUp(&value, "连接排队等太久", strong: false, at, &changes) : false
        }
    }

    @discardableResult
    public func pushback(status: Int) -> Bool {
        mutate { value, at, changes in
            Self.stepDown(&value, target: max(0, value.level - 1), restLevel: value.level, "服务器返回 \(status)",
                          restMs: Self.pushbackRestMs, hard: true, at, &changes)
        }
    }

    public func newSession() {
        mutate { value, at, changes in
            value.aheadSamples.removeAll()
            value.pressureSince = 0
            value.trial = nil
            value.buckets.removeAll()
            value.saturatedSpans.removeAll()
            if value.saturated { value.saturatedSince = at }
            let base = value.startup?.base ?? value.level
            let target = Self.startupTarget(&value, at)
            if target > value.level {
                Self.setLevel(&value, target, "开头先用 \(Self.ladder[target]) 线程", nil, at, &changes)
            }
            value.startup = value.level > base ? Startup(base: base, until: at + Self.startupMaxMs) : nil
        }
    }

    private func mutate<Result>(_ body: (inout State, Double, inout [Change]) -> Result) -> Result {
        let at = clock.nowMs()
        var changes: [Change] = []
        let result = state.withLock { body(&$0, at, &changes) }
        if !changes.isEmpty, let notify = handler.current {
            for change in changes { notify(change.threads, change.previous, change.reason) }
        }
        return result
    }

    private static func pruneBuckets(_ value: inout State, _ at: Double) {
        while let first = value.buckets.first, at - first.at > windowMs { value.buckets.removeFirst() }
    }

    /// Bytes per second over the window, timed from first to last delivery so an idle tail is not slowness.
    private static func throughput(_ value: inout State, _ at: Double) -> Double {
        pruneBuckets(&value, at)
        guard let first = value.buckets.first, let last = value.buckets.last else { return 0 }
        let bytes = value.buckets.reduce(0) { $0 + $1.bytes }
        return bytes * 1000 / max(1000, last.at - first.at + bucketMs)
    }

    private static func saturation(_ value: inout State, _ at: Double) -> Double {
        let from = at - windowMs
        value.saturatedSpans.removeAll { $0.to <= from }
        var busy = value.saturatedSpans.reduce(0) { $0 + max(0, $1.to - max($1.from, from)) }
        if value.saturated { busy += max(0, at - max(value.saturatedSince, from)) }
        return min(1, busy / windowMs)
    }

    private static func resting(_ value: inout State, _ level: Int, _ at: Double) -> Rest? {
        guard let rest = value.resting[level] else { return nil }
        if rest.until <= at {
            value.resting[level] = nil
            return nil
        }
        return rest
    }

    private static func setLevel(_ value: inout State, _ level: Int, _ reason: String, _ trial: Trial?, _ at: Double, _ changes: inout [Change]) {
        let previous = ladder[value.level]
        value.level = level
        value.changedAt = at
        value.reason = reason
        value.steps += 1
        value.trial = trial
        value.pressureSince = 0
        changes.append((ladder[level], previous, reason))
    }

    private static func stepUp(_ value: inout State, _ reason: String, strong: Bool, _ at: Double, _ changes: inout [Change]) -> Bool {
        if at - value.changedAt < stepCooldownMs { return false }
        if resting(&value, value.level, at)?.hard == true { return false }
        var next = value.level + 1
        while next < ladder.count {
            guard let rest = resting(&value, next, at) else { break }
            if rest.hard || !strong { return false }
            next += 1
        }
        if next >= ladder.count { return false }
        let trial = Trial(from: value.level, level: next, at: at, baseline: throughput(&value, at), stalled: false)
        setLevel(&value, next, reason, trial, at, &changes)
        value.startup = nil
        return true
    }

    private static func startupTarget(_ value: inout State, _ at: Double) -> Int {
        if resting(&value, value.level, at)?.hard == true { return value.level }
        var level = value.level
        while level < startupLevel && resting(&value, level + 1, at)?.hard != true { level += 1 }
        return level
    }

    private static func stepDown(_ value: inout State, target: Int, restLevel: Int, _ reason: String, restMs: Double, hard: Bool,
                                 _ at: Double, _ changes: inout [Change]) -> Bool {
        value.resting[restLevel] = Rest(until: at + restMs, hard: hard)
        if target >= value.level { return false }
        setLevel(&value, target, reason, nil, at, &changes)
        return true
    }

    private static func judgeTrial(_ value: inout State, _ at: Double, _ changes: inout [Change]) {
        guard let trial = value.trial, at - trial.at >= trialMs else { return }
        value.trial = nil
        if trial.stalled || saturation(&value, at) < 0.6 || trial.baseline <= 0 { return }
        if throughput(&value, at) < trial.baseline {
            _ = stepDown(&value, target: trial.from, restLevel: trial.level,
                         "\(ladder[trial.level]) 线程没有比 \(ladder[trial.from]) 线程更快", restMs: restMs, hard: false, at, &changes)
        }
    }
}
