import Foundation

public struct MonotonicClock: Sendable {
    public let nowMs: @Sendable () -> Double

    public init(nowMs: @escaping @Sendable () -> Double) {
        self.nowMs = nowMs
    }

    public static let system = MonotonicClock { ProcessInfo.processInfo.systemUptime * 1000 }
}

/// Test clock whose time only moves when told to.
public final class ManualClock: @unchecked Sendable {
    private let value: Locked<Double>

    public init(_ start: Double = 0) {
        value = Locked(start)
    }

    public func advance(_ ms: Double) { value.withLock { $0 += ms } }
    public func set(_ ms: Double) { value.withLock { $0 = ms } }
    public var clock: MonotonicClock { MonotonicClock { [value] in value.current } }
}

public func sleepMs(_ ms: Double) async throws {
    guard ms > 0 else {
        try Task.checkCancellation()
        return
    }
    try await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
}
