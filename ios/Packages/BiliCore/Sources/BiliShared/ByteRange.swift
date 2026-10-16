import Foundation

public struct ByteRange: Hashable, Sendable, CustomStringConvertible {
    public let start: Int64
    /// Inclusive, like HTTP Range and Bilibili's SegmentBase notation.
    public let end: Int64

    public init?(start: Int64, end: Int64) {
        guard start >= 0, end >= start else { return nil }
        self.start = start
        self.end = end
    }

    public var length: Int64 { end - start + 1 }
    public var description: String { "\(start)-\(end)" }
    public var headerValue: String { "bytes=\(start)-\(end)" }

    public func contains(_ other: ByteRange) -> Bool {
        other.start >= start && other.end <= end
    }

    /// Bilibili's "a-b" notation from SegmentBase.
    public static func parse(_ text: String) -> ByteRange? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int64(parts[0]), let end = Int64(parts[1]) else { return nil }
        return ByteRange(start: start, end: end)
    }

    /// BTR range-core `splitRange`: at most `concurrency` pieces, none smaller than `minChunk`
    /// (and never below 32 KiB), sizes differing by at most one byte.
    public func split(concurrency: Int, minChunk: Int64) -> [ByteRange] {
        let limit = Int64(max(1, min(512, concurrency)))
        let minimum = max(32 * 1024, minChunk)
        let count = max(1, min(limit, (length + minimum - 1) / minimum))
        let base = length / count
        let remainder = length % count
        var pieces: [ByteRange] = []
        var cursor = start
        for index in 0..<count {
            let size = base + (index < remainder ? 1 : 0)
            pieces.append(ByteRange(start: cursor, end: cursor + size - 1)!)
            cursor += size
        }
        return pieces
    }
}

public struct ContentRange: Equatable, Sendable {
    public let range: ByteRange
    public let total: Int64?

    public init(range: ByteRange, total: Int64?) {
        self.range = range
        self.total = total
    }

    /// "bytes a-b/total" or "bytes a-b/*".
    public static func parse(_ text: String?) -> ContentRange? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), text.hasPrefix("bytes ") else { return nil }
        let halves = text.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count == 2, let range = ByteRange.parse(String(halves[0])) else { return nil }
        if halves[1] == "*" { return ContentRange(range: range, total: nil) }
        guard let total = Int64(halves[1]), total > range.end else { return nil }
        return ContentRange(range: range, total: total)
    }
}
