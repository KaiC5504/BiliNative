import Foundation

public struct DanmakuElem: Sendable, Equatable {
    public var id: Int64
    public var progressMs: Int64
    public var mode: Int
    public var fontSize: Int
    public var color: UInt32
    public var midHash: String
    public var content: String
    public var ctime: Int64
    public var weight: Int
    public var pool: Int
    public var idStr: String
    public var attr: Int
    public var colorful: Int

    public init(id: Int64 = 0, progressMs: Int64 = 0, mode: Int = 1, fontSize: Int = 25, color: UInt32 = 0xFFFFFF,
                midHash: String = "", content: String = "", ctime: Int64 = 0, weight: Int = 0, pool: Int = 0,
                idStr: String = "", attr: Int = 0, colorful: Int = 0) {
        self.id = id
        self.progressMs = progressMs
        self.mode = mode
        self.fontSize = fontSize
        self.color = color
        self.midHash = midHash
        self.content = content
        self.ctime = ctime
        self.weight = weight
        self.pool = pool
        self.idStr = idStr
        self.attr = attr
        self.colorful = colorful
    }

    public static func decode(_ data: Data) throws -> DanmakuElem {
        var elem = DanmakuElem(mode: 0, fontSize: 0, color: 0)
        var reader = ProtobufReader(data)
        while let (field, wireType) = try reader.next() {
            // A known field arriving in another wire type is skipped rather than misread.
            switch (field, wireType) {
            case (1, 0): elem.id = Int64(bitPattern: try reader.varint())
            case (2, 0): elem.progressMs = Int64(bitPattern: try reader.varint())
            case (3, 0): elem.mode = Int(truncatingIfNeeded: try reader.varint())
            case (4, 0): elem.fontSize = Int(truncatingIfNeeded: try reader.varint())
            case (5, 0): elem.color = UInt32(truncatingIfNeeded: try reader.varint())
            case (6, 2): elem.midHash = string(try reader.lengthDelimited())
            case (7, 2): elem.content = string(try reader.lengthDelimited())
            case (8, 0): elem.ctime = Int64(bitPattern: try reader.varint())
            case (9, 0): elem.weight = Int(truncatingIfNeeded: try reader.varint())
            case (11, 0): elem.pool = Int(truncatingIfNeeded: try reader.varint())
            case (12, 2): elem.idStr = string(try reader.lengthDelimited())
            case (13, 0): elem.attr = Int(truncatingIfNeeded: try reader.varint())
            case (24, 0): elem.colorful = Int(truncatingIfNeeded: try reader.varint())
            default: try reader.skip(wireType: wireType)
            }
        }
        return elem
    }

    private static func string(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }
}
