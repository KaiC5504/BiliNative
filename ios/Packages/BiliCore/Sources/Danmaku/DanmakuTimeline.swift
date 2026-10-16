import Foundation

/// Hands out each danmaku once as the playhead passes it. The player's time drives it, so a stall or
/// a seek never repeats or skips what was already shown.
public struct DanmakuTimeline: Sendable {
    private var items: [DisplayDanmaku] = []
    private var last: Int64 = -1
    private static let maxStepMs: Int64 = 1_000

    public init() {}

    public mutating func add(_ items: [DisplayDanmaku]) {
        guard !items.isEmpty else { return }
        self.items.append(contentsOf: items)
        // The sort must be stable: danmaku at the same millisecond keep the order they arrived in.
        self.items = self.items.enumerated()
            .sorted { ($0.element.elem.progressMs, $0.offset) < ($1.element.elem.progressMs, $1.offset) }
            .map(\.element)
    }

    public mutating func advance(to ms: Int64) -> [DisplayDanmaku] {
        if ms < last || ms - last > Self.maxStepMs {
            seek(to: ms)
            return []
        }
        let start = firstIndex(after: last)
        var end = start
        while end < items.count, items[end].elem.progressMs <= ms { end += 1 }
        last = ms
        return Array(items[start..<end])
    }

    public mutating func seek(to ms: Int64) {
        last = ms
    }

    /// Index of the first item with `progressMs > ms`.
    private func firstIndex(after ms: Int64) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if items[mid].elem.progressMs <= ms { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
