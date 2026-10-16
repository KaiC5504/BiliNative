import BiliShared

func smoothed(_ old: Double, _ sample: Double) -> Double {
    old > 0 ? old * 0.7 + sample * 0.3 : sample
}

/// What one connection typically delivers and how long a piece typically takes (BTR `meter`).
final class Meter: @unchecked Sendable {
    /// Shorter transfers are mostly round trip and say nothing about speed.
    static let sampleMinBytes: Int64 = 48 * 1024

    private let state = Locked((bps: 0.0, pieceMs: 0.0))

    var connectionBps: Double { state.current.bps }
    var pieceMs: Double { state.current.pieceMs }

    func record(bytes: Int64, elapsedMs: Double) {
        guard bytes >= Self.sampleMinBytes, elapsedMs > 0 else { return }
        let bps = Double(bytes) * 1000 / elapsedMs
        state.withLock { value in
            value.bps = smoothed(value.bps, bps)
            value.pieceMs = smoothed(value.pieceMs, elapsedMs)
        }
    }

    /// A piece should keep its connection busy for a good part of a second; 64 KiB until the speed
    /// is known, never above 1 MiB, and small enough that a range still spreads over the nodes.
    func adaptiveMinChunk(base: Int64, rangeLength: Int64, pieceLimit: Int, hostCount: Int) -> Int64 {
        let bps = connectionBps
        guard bps > 0 else { return base }
        let target = Int64(bps * 0.6 / 65_536) * 65_536
        let ways = Int64(max(1, min(max(4, hostCount), pieceLimit)))
        let spread = (rangeLength + ways - 1) / ways
        return max(base, min(1 << 20, target, spread))
    }

    func hedgeDelayMs(configured: Double) -> Double {
        let typical = pieceMs
        return typical > 0 ? max(250, min(configured, (typical * 1.5).rounded())) : configured
    }
}
