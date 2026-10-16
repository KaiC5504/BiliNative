public struct BoxHeader: Equatable, Sendable {
    public let type: String
    public let start: Int
    public let headerSize: Int
    /// Exclusive.
    public let end: Int

    public var payloadStart: Int { start + headerSize }
}

public enum BoxReader {
    public static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    public static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }

    public static func uint64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(bytes[offset + $1]) }
    }

    static func type(_ bytes: [UInt8], _ offset: Int) -> String {
        String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
    }

    /// Sibling boxes between `from` and `to`. Stops at the first malformed or truncated box, so a
    /// buffer that ends mid-file still yields the complete boxes before the cut.
    public static func boxes(in bytes: [UInt8], from: Int, to: Int) -> [BoxHeader] {
        var result: [BoxHeader] = []
        var offset = from
        let limit = min(to, bytes.count)
        while offset >= 0, offset + 8 <= limit {
            var size = Int(uint32(bytes, offset))
            var header = 8
            if size == 1 {
                guard offset + 16 <= limit else { break }
                let large = uint64(bytes, offset + 8)
                guard large <= UInt64(Int.max) else { break }
                size = Int(large)
                header = 16
            } else if size == 0 {
                size = limit - offset
            }
            // Compared as a remaining length so a hostile 64-bit size cannot overflow the addition.
            guard size >= header, size <= limit - offset else { break }
            result.append(BoxHeader(type: type(bytes, offset + 4), start: offset, headerSize: header, end: offset + size))
            offset += size
        }
        return result
    }
}
