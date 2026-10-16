import BiliShared

public struct NodeTiming: Equatable, Sendable {
    public var node: String
    public var requests = 0
    public var failures = 0
    /// Smoothed time to response headers.
    public var firstByteMs: Double = 0

    public init(node: String) {
        self.node = node
    }
}

public struct RipperStats: Equatable, Sendable {
    public var deliveredBytes: Int64 = 0
    /// Bytes from copies that lost a race or failed.
    public var duplicateBytes: Int64 = 0
    public var requests = 0
    public var failures = 0
    public var cacheHits = 0
    public var cacheMisses = 0
    public var concurrency = 0
    public var nodes: [NodeTiming] = []
    public var nodeStates: [Resolver.NodeStatus] = []

    public init() {}

    public var duplicateShare: Double {
        let total = deliveredBytes + duplicateBytes
        return total > 0 ? Double(duplicateBytes) / Double(total) : 0
    }
}

final class EngineStats: @unchecked Sendable {
    private let state = Locked((stats: RipperStats(), timings: [String: NodeTiming]()))

    func started(node: String) {
        state.withLock { value in
            value.stats.requests += 1
            value.timings[node, default: NodeTiming(node: node)].requests += 1
        }
    }

    func firstByte(node: String, ms: Double) {
        state.withLock { value in
            var timing = value.timings[node, default: NodeTiming(node: node)]
            timing.firstByteMs = smoothed(timing.firstByteMs, ms)
            value.timings[node] = timing
        }
    }

    func failed(node: String, wastedBytes: Int64, cancelled: Bool) {
        state.withLock { value in
            value.stats.duplicateBytes += wastedBytes
            if !cancelled {
                value.stats.failures += 1
                value.timings[node, default: NodeTiming(node: node)].failures += 1
            }
        }
    }

    func delivered(_ bytes: Int64) {
        state.withLock { $0.stats.deliveredBytes += bytes }
    }

    func cache(hit: Bool) {
        state.withLock { value in
            if hit { value.stats.cacheHits += 1 } else { value.stats.cacheMisses += 1 }
        }
    }

    func snapshot() -> RipperStats {
        state.withLock { value in
            var stats = value.stats
            stats.nodes = value.timings.values.sorted { $0.node < $1.node }
            return stats
        }
    }
}
