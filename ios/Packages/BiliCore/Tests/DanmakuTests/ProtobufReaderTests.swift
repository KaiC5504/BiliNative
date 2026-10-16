import XCTest
@testable import Danmaku

final class ProtobufReaderTests: XCTestCase {
    func testReadsMultiByteVarintsAndFieldTags() throws {
        var w = ProtobufWriter()
        w.varint(1, 300)
        w.varint(2, UInt64.max)
        var r = ProtobufReader(w.data)
        let first = try XCTUnwrap(try r.next())
        XCTAssertEqual(first.field, 1)
        XCTAssertEqual(first.wireType, 0)
        XCTAssertEqual(try r.varint(), 300)
        _ = try r.next()
        XCTAssertEqual(try r.varint(), UInt64.max)
        XCTAssertNil(try r.next())
    }

    func testLengthDelimitedReturnsTheBytesAndAdvances() throws {
        var w = ProtobufWriter()
        w.string(3, "弹幕")
        w.varint(4, 9)
        var r = ProtobufReader(w.data)
        XCTAssertEqual(try r.next()?.wireType, 2)
        XCTAssertEqual(String(decoding: try r.lengthDelimited(), as: UTF8.self), "弹幕")
        XCTAssertEqual(try r.next()?.field, 4)
    }

    func testSkipPassesEveryKnownWireTypeAndRejectsTheRest() throws {
        var w = ProtobufWriter()
        w.varint(1, 5)
        w.fixed64(2, 7)
        w.string(3, "x")
        w.fixed32(4, 9)
        w.varint(5, 1)
        var r = ProtobufReader(w.data)
        var seen: [Int] = []
        while let (field, wireType) = try r.next() {
            seen.append(field)
            try r.skip(wireType: wireType)
        }
        XCTAssertEqual(seen, [1, 2, 3, 4, 5])
        var r2 = ProtobufReader(Data([0x0B]))
        let tag = try XCTUnwrap(try r2.next())
        XCTAssertEqual(tag.wireType, 3)
        XCTAssertThrowsError(try r2.skip(wireType: 3)) { XCTAssertEqual($0 as? ProtobufError, .badWireType(3)) }
    }

    func testTruncatedInputThrows() {
        var overlong = ProtobufReader(Data([0x80]))
        XCTAssertThrowsError(try overlong.varint()) { XCTAssertEqual($0 as? ProtobufError, .truncated) }

        var w = ProtobufWriter()
        w.string(1, "hello")
        var short = ProtobufReader(w.data.dropLast())
        _ = try? short.next()
        XCTAssertThrowsError(try short.lengthDelimited()) { XCTAssertEqual($0 as? ProtobufError, .truncated) }

        var f = ProtobufWriter()
        f.fixed64(1, 1)
        var fixed = ProtobufReader(f.data.dropLast())
        XCTAssertEqual(try fixed.next()?.wireType, 1)
        XCTAssertThrowsError(try fixed.skip(wireType: 1)) { XCTAssertEqual($0 as? ProtobufError, .truncated) }
    }

    func testAReaderOverASliceKeepsItsOwnOffsets() throws {
        var w = ProtobufWriter()
        w.varint(1, 1)
        w.varint(2, 2)
        let padded = Data([0xFF, 0xFF]) + w.data
        var r = ProtobufReader(padded.dropFirst(2))
        XCTAssertEqual(try r.next()?.field, 1)
        XCTAssertEqual(try r.varint(), 1)
        XCTAssertEqual(try r.next()?.field, 2)
    }
}
