import Foundation

/// Test-only encoder; the production target only reads protobuf.
struct ProtobufWriter {
    private(set) var data = Data()

    private mutating func rawVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private mutating func tag(_ field: Int, _ wireType: Int) {
        rawVarint(UInt64(field << 3 | wireType))
    }

    mutating func varint(_ field: Int, _ value: UInt64) {
        tag(field, 0)
        rawVarint(value)
    }

    mutating func varint(_ field: Int, _ value: Int) {
        varint(field, UInt64(bitPattern: Int64(value)))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, 2)
        rawVarint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    mutating func fixed32(_ field: Int, _ value: UInt32) {
        tag(field, 5)
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }

    mutating func fixed64(_ field: Int, _ value: UInt64) {
        tag(field, 1)
        for shift in stride(from: 0, to: 64, by: 8) { data.append(UInt8((value >> UInt64(shift)) & 0xFF)) }
    }
}
