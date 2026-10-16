import XCTest
@testable import Danmaku

final class SegmentTests: XCTestCase {
    private func elemBytes(_ progress: Int, _ text: String) -> Data {
        var w = ProtobufWriter()
        w.varint(2, progress)
        w.varint(3, 1)
        w.varint(5, 0xFFFFFF)
        w.string(7, text)
        return w.data
    }

    func testDecodesAnElementAndSkipsUnknownFields() throws {
        var w = ProtobufWriter()
        w.varint(1, 7); w.varint(2, 61_500); w.varint(3, 5); w.varint(4, 25); w.varint(5, 0xFE0302)
        w.string(6, "1a2b3c4d"); w.string(7, "前方高能"); w.varint(9, 8); w.fixed32(99, 1); w.varint(24, 60001)
        let e = try DanmakuElem.decode(w.data)
        XCTAssertEqual(e.id, 7)
        XCTAssertEqual(e.progressMs, 61_500); XCTAssertEqual(e.mode, 5); XCTAssertEqual(e.color, 0xFE0302)
        XCTAssertEqual(e.fontSize, 25); XCTAssertEqual(e.midHash, "1a2b3c4d"); XCTAssertEqual(e.weight, 8)
        XCTAssertEqual(e.content, "前方高能"); XCTAssertEqual(e.colorful, 60001)
    }

    func testReadsTheLessCommonFields() throws {
        var w = ProtobufWriter()
        w.varint(8, 1_702_204_169); w.varint(11, 1); w.string(12, "9007199254740993"); w.varint(13, 2)
        w.fixed64(77, 5); w.string(78, "ignored")
        let e = try DanmakuElem.decode(w.data)
        XCTAssertEqual(e.ctime, 1_702_204_169); XCTAssertEqual(e.pool, 1)
        XCTAssertEqual(e.idStr, "9007199254740993"); XCTAssertEqual(e.attr, 2)
    }

    func testAKnownFieldInTheWrongWireTypeIsSkippedNotMisread() throws {
        var w = ProtobufWriter()
        w.string(2, "not a number")
        w.string(7, "still read")
        let e = try DanmakuElem.decode(w.data)
        XCTAssertEqual(e.progressMs, 0)
        XCTAssertEqual(e.content, "still read")
    }

    func testSegmentWithStateOneIsClosed() throws {
        var w = ProtobufWriter()
        w.bytes(1, elemBytes(1_000, "甲"))
        w.bytes(1, elemBytes(2_000, "乙"))
        w.varint(2, 1)
        let segment = try DanmakuSegment.decode(w.data)
        XCTAssertTrue(segment.closed)
        XCTAssertEqual(segment.elems.map(\.content), ["甲", "乙"])
        XCTAssertEqual(segment.elems.map(\.progressMs), [1_000, 2_000])
    }

    func testSegmentWithoutStateIsOpen() throws {
        var w = ProtobufWriter()
        w.bytes(1, elemBytes(1_000, "甲"))
        w.bytes(3, Data([1, 2, 3]))
        let segment = try DanmakuSegment.decode(w.data)
        XCTAssertFalse(segment.closed)
        XCTAssertEqual(segment.elems.count, 1)
    }

    func testEmptyReplyIsAnEmptyOpenSegment() throws {
        let segment = try DanmakuSegment.decode(Data())
        XCTAssertTrue(segment.elems.isEmpty)
        XCTAssertFalse(segment.closed)
    }

    func testTruncatedInputThrows() throws {
        var w = ProtobufWriter()
        w.varint(2, 61_500); w.string(7, "前方高能"); w.varint(24, 60001)
        XCTAssertThrowsError(try DanmakuElem.decode(w.data.dropLast())) { XCTAssertEqual($0 as? ProtobufError, .truncated) }

        var s = ProtobufWriter()
        s.bytes(1, elemBytes(1_000, "甲"))
        XCTAssertThrowsError(try DanmakuSegment.decode(s.data.dropLast())) { XCTAssertEqual($0 as? ProtobufError, .truncated) }
    }

    func testSegmentIndexIsOneBasedSixMinutes() {
        XCTAssertEqual(DanmakuSegments.index(forMs: 0), 1)
        XCTAssertEqual(DanmakuSegments.index(forMs: 359_999), 1)
        XCTAssertEqual(DanmakuSegments.index(forMs: 360_000), 2)
        XCTAssertEqual(DanmakuSegments.index(forMs: -5), 1)
    }

    func testNeededPrefetchesNearTheBoundaryOnly() {
        XCTAssertEqual(DanmakuSegments.needed(atMs: 10_000, loaded: [], durationMs: 900_000), [1])
        XCTAssertEqual(DanmakuSegments.needed(atMs: 335_000, loaded: [1], durationMs: 900_000), [2])
        XCTAssertEqual(DanmakuSegments.needed(atMs: 335_000, loaded: [1], durationMs: 350_000), [])
        XCTAssertEqual(DanmakuSegments.needed(atMs: 10_000, loaded: [1], durationMs: 900_000), [])
        XCTAssertEqual(DanmakuSegments.needed(atMs: 335_000, loaded: [], durationMs: 900_000), [1, 2])
        XCTAssertEqual(DanmakuSegments.needed(atMs: 335_000, loaded: [1, 2], durationMs: 900_000), [])
    }
}
