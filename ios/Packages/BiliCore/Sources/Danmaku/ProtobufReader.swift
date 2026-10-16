import Foundation

public enum ProtobufError: Error, Equatable {
    case truncated
    case badWireType(Int)
}

/// Just enough protobuf to read Bilibili's danmaku replies without a package.
public struct ProtobufReader {
    private let data: Data
    private var position: Data.Index

    public init(_ data: Data) {
        self.data = data
        self.position = data.startIndex
    }

    /// The next field's number and wire type, or nil at the end of the input.
    public mutating func next() throws -> (field: Int, wireType: Int)? {
        guard position < data.endIndex else { return nil }
        let tag = try varint()
        return (Int(truncatingIfNeeded: tag >> 3), Int(tag & 7))
    }

    public mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while position < data.endIndex {
            let byte = data[position]
            position = data.index(after: position)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            // A varint is at most 10 bytes; more is not a protobuf we can read.
            if shift > 63 { throw ProtobufError.truncated }
        }
        throw ProtobufError.truncated
    }

    public mutating func lengthDelimited() throws -> Data {
        let length = try varint()
        guard length <= UInt64(data.endIndex - position) else { throw ProtobufError.truncated }
        let end = position + Int(length)
        defer { position = end }
        return Data(data[position..<end])
    }

    public mutating func skip(wireType: Int) throws {
        switch wireType {
        case 0: _ = try varint()
        case 1: try advance(8)
        case 2: _ = try lengthDelimited()
        case 5: try advance(4)
        default: throw ProtobufError.badWireType(wireType)
        }
    }

    private mutating func advance(_ count: Int) throws {
        guard count <= data.endIndex - position else { throw ProtobufError.truncated }
        position += count
    }
}
