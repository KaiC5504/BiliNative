import Foundation

public struct DanmakuSegment: Sendable {
    public var elems: [DanmakuElem]
    /// The uploader turned danmaku off for this video.
    public var closed: Bool

    public init(elems: [DanmakuElem], closed: Bool) {
        self.elems = elems
        self.closed = closed
    }

    public static func decode(_ data: Data) throws -> DanmakuSegment {
        var elems: [DanmakuElem] = []
        var state: UInt64 = 0
        var reader = ProtobufReader(data)
        while let (field, wireType) = try reader.next() {
            switch (field, wireType) {
            case (1, 2): elems.append(try DanmakuElem.decode(try reader.lengthDelimited()))
            case (2, 0): state = try reader.varint()
            default: try reader.skip(wireType: wireType)
            }
        }
        return DanmakuSegment(elems: elems, closed: state == 1)
    }
}

public enum DanmakuSegments {
    public static let lengthMs: Int64 = 360_000
    private static let prefetchWindowMs: Int64 = 30_000

    /// 1-based, as the seg.so endpoint counts.
    public static func index(forMs ms: Int64) -> Int {
        Int(max(ms, 0) / lengthMs) + 1
    }

    public static func needed(atMs ms: Int64, loaded: Set<Int>, durationMs: Int64) -> [Int] {
        let current = index(forMs: ms)
        var wanted: [Int] = []
        if !loaded.contains(current) { wanted.append(current) }
        let boundary = Int64(current) * lengthMs
        if boundary - ms <= prefetchWindowMs, durationMs > boundary, !loaded.contains(current + 1) {
            wanted.append(current + 1)
        }
        return wanted
    }
}
