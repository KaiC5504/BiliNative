import XCTest
import BiliShared
@testable import DashHLS

final class SidxParserTests: XCTestCase {
    func testVersion0AfterAnotherBox() throws {
        let bytes = MP4Builder.box("free", []) + MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0,
                                                                  refs: [(1000, 2000), (2000, 2000), (1500, 1000)])
        let segments = try XCTUnwrap(SidxParser.parse(bytes, absoluteStart: 500))
        // sidx is 68 bytes at offset 8, so media starts at 500 + 76.
        XCTAssertEqual(segments.map(\.range), [ByteRange(start: 576, end: 1575), ByteRange(start: 1576, end: 3575), ByteRange(start: 3576, end: 5075)])
        XCTAssertEqual(segments.map(\.startTime), [0, 2, 4])
        XCTAssertEqual(segments.map(\.duration), [2, 2, 1])
        XCTAssertEqual(segments.map(\.index), [0, 1, 2])
    }

    func testVersion1WithEarliestTimeAndOffset() throws {
        let bytes = MP4Builder.sidx(version: 1, timescale: 90000, earliest: 90000, firstOffset: 10, refs: [(4000, 180000)])
        let segment = try XCTUnwrap(SidxParser.parse(bytes, absoluteStart: 0)?.first)
        XCTAssertEqual(segment.startTime, 1)
        XCTAssertEqual(segment.duration, 2)
        XCTAssertEqual(segment.range.start, Int64(bytes.count) + 10)
    }

    func testHierarchicalReferenceRejectsTheWholeIndex() {
        let bytes = MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(0x8000_0000 | 100, 10), (200, 10)])
        XCTAssertNil(SidxParser.parse(bytes, absoluteStart: 0))
    }

    func testUnknownVersionAndZeroSizeReferenceAreRejected() {
        XCTAssertNil(SidxParser.parse(MP4Builder.sidx(version: 2, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(10, 10)]), absoluteStart: 0))
        XCTAssertNil(SidxParser.parse(MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(0, 10)]), absoluteStart: 0))
    }

    func testRejectsBrokenInput() {
        XCTAssertNil(SidxParser.parse([1, 2, 3], absoluteStart: 0))
        XCTAssertNil(SidxParser.parse(MP4Builder.box("free", [0, 0]), absoluteStart: 0))
        XCTAssertNil(SidxParser.parse(MP4Builder.sidx(version: 0, timescale: 0, earliest: 0, firstOffset: 0, refs: [(10, 10)]), absoluteStart: 0))
    }

    func testBoxReaderStopsAtTruncatedBox() {
        let bytes = MP4Builder.box("ftyp", [1, 2, 3, 4]) + MP4Builder.be32(100) + Array("moov".utf8)
        XCTAssertEqual(BoxReader.boxes(in: bytes, from: 0, to: bytes.count).map(\.type), ["ftyp"])
    }

    func testTruncatedSidxReturnsNilForBothVersions() {
        for version: UInt8 in [0, 1] {
            let full = MP4Builder.sidx(version: version, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(10, 10), (10, 10)])
            XCTAssertNotNil(SidxParser.parse(full, absoluteStart: 0))
            for length in 0..<full.count {
                XCTAssertNil(SidxParser.parse(Array(full.prefix(length)), absoluteStart: 0), "version \(version), \(length) bytes")
            }
        }
    }

    func testBoxSizeCoversPayloadTooShortForVersion1Header() {
        // The box is well-formed, but its payload ends before the 64-bit fields do.
        let payload: [UInt8] = [1, 0, 0, 0] + MP4Builder.be32(1) + MP4Builder.be32(1000) + MP4Builder.be64(0)
        XCTAssertNil(SidxParser.parse(MP4Builder.box("sidx", payload), absoluteStart: 0))
    }

    func testReferenceCountLargerThanAvailableBytesIsRejected() {
        var payload: [UInt8] = [0, 0, 0, 0] + MP4Builder.be32(1) + MP4Builder.be32(1000) + MP4Builder.be32(0) + MP4Builder.be32(0)
        payload += [0, 0] + MP4Builder.be16(60_000)
        payload += MP4Builder.be32(10) + MP4Builder.be32(10) + MP4Builder.be32(0)
        XCTAssertNil(SidxParser.parse(MP4Builder.box("sidx", payload), absoluteStart: 0))
    }

    func testLargeIndexesParseUpToTheSixteenBitReferenceLimit() throws {
        for count in [10_001, Int(UInt16.max)] {
            let refs = [(UInt32, UInt32)](repeating: (100, 10), count: count)
            let bytes = MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: refs)
            let segments = try XCTUnwrap(SidxParser.parse(bytes, absoluteStart: 0), "\(count) references")
            XCTAssertEqual(segments.count, count)
            XCTAssertEqual(segments.last?.range.end, Int64(bytes.count) + Int64(count) * 100 - 1)
        }
    }

    func testHugeOffsetsAndSizesDoNotTrap() {
        let hugeOffset = MP4Builder.sidx(version: 1, timescale: 1000, earliest: UInt64.max, firstOffset: UInt64.max, refs: [(10, 10)])
        XCTAssertNil(SidxParser.parse(hugeOffset, absoluteStart: 0))
        let nearLimit = MP4Builder.sidx(version: 1, timescale: 1000, earliest: 0, firstOffset: UInt64(Int64.max) - 10, refs: [(0x7fff_ffff, 10)])
        XCTAssertNil(SidxParser.parse(nearLimit, absoluteStart: 100))
        let hugeStart = MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(10, 10)])
        XCTAssertNil(SidxParser.parse(hugeStart, absoluteStart: Int64.max))
    }

    func testBoxReaderRejectsHugeSizes() {
        let largeSize = MP4Builder.be32(1) + Array("free".utf8) + MP4Builder.be64(UInt64(Int.max))
        XCTAssertTrue(BoxReader.boxes(in: largeSize, from: 0, to: largeSize.count).isEmpty)
        let belowHeader = MP4Builder.be32(1) + Array("free".utf8) + MP4Builder.be64(4)
        XCTAssertTrue(BoxReader.boxes(in: belowHeader, from: 0, to: belowHeader.count).isEmpty)
        let tail = MP4Builder.be32(0) + Array("mdat".utf8) + [1, 2, 3]
        XCTAssertEqual(BoxReader.boxes(in: tail, from: 0, to: tail.count).map(\.end), [11])
    }
}
