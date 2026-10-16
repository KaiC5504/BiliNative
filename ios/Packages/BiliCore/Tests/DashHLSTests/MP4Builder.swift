enum MP4Builder {
    static func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xff)] }
    static func be32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (24 - 8 * UInt32($0))) & 0xff) } }
    static func be64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8((value >> (56 - 8 * UInt64($0))) & 0xff) } }

    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(8 + payload.count)) + Array(type.utf8) + payload
    }

    /// refs: (reference word including the type bit, duration in timescale units)
    static func sidx(version: UInt8, timescale: UInt32, earliest: UInt64, firstOffset: UInt64, refs: [(UInt32, UInt32)]) -> [UInt8] {
        var payload: [UInt8] = [version, 0, 0, 0] + be32(1) + be32(timescale)
        if version == 0 {
            payload += be32(UInt32(earliest)) + be32(UInt32(firstOffset))
        } else {
            payload += be64(earliest) + be64(firstOffset)
        }
        payload += [0, 0] + be16(UInt16(refs.count))
        for (reference, duration) in refs {
            payload += be32(reference) + be32(duration) + be32(0x9000_0000)
        }
        return box("sidx", payload)
    }

    static func hvcC(nalTypes: [UInt8]) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 22) + [UInt8(nalTypes.count)]
        for type in nalTypes {
            payload += [type & 0x3f] + be16(1) + be16(2) + [0xAA, 0xBB]
        }
        return box("hvcC", payload)
    }

    static func initSegment(entryType: String, nalTypes: [UInt8]) -> [UInt8] {
        let entry = box(entryType, [UInt8](repeating: 0, count: 78) + hvcC(nalTypes: nalTypes))
        let stsd = box("stsd", [0, 0, 0, 0] + be32(1) + entry)
        let trak = box("trak", box("tkhd", [UInt8](repeating: 0, count: 84)) + box("mdia", box("minf", box("stbl", stsd))))
        let moov = box("moov", box("mvhd", [UInt8](repeating: 0, count: 100)) + trak)
        return box("ftyp", Array("iso6".utf8) + be32(0)) + moov
    }
}
