import XCTest
@testable import BiliShared

final class ByteRangeTests: XCTestCase {
    func testParseBilibiliNotation() {
        XCTAssertEqual(ByteRange.parse("0-1234"), ByteRange(start: 0, end: 1234))
        XCTAssertEqual(ByteRange.parse("0-1234")?.length, 1235)
        XCTAssertNil(ByteRange.parse("12-3"))
        XCTAssertNil(ByteRange.parse("abc"))
        XCTAssertNil(ByteRange(start: -1, end: 4))
    }

    func testHeaderValueAndContains() {
        let outer = ByteRange(start: 10, end: 99)!
        XCTAssertEqual(outer.headerValue, "bytes=10-99")
        XCTAssertTrue(outer.contains(ByteRange(start: 20, end: 30)!))
        XCTAssertFalse(outer.contains(ByteRange(start: 90, end: 100)!))
    }

    func testContentRange() {
        let parsed = ContentRange.parse("bytes 100-199/1000")
        XCTAssertEqual(parsed?.range, ByteRange(start: 100, end: 199))
        XCTAssertEqual(parsed?.total, 1000)
        XCTAssertNotNil(ContentRange.parse("bytes 0-9/*"))
        XCTAssertNil(ContentRange.parse("bytes 0-9/*")?.total)
        XCTAssertNil(ContentRange.parse("bytes 0-9/5"))
        XCTAssertNil(ContentRange.parse("items 0-9/50"))
        XCTAssertNil(ContentRange.parse(nil))
    }

    func testSplitMatchesBTR() {
        let mebibyte = ByteRange(start: 0, end: 1_048_575)!
        XCTAssertEqual(mebibyte.split(concurrency: 4, minChunk: 65_536).map(\.length), [262_144, 262_144, 262_144, 262_144])
        XCTAssertEqual(ByteRange(start: 0, end: 99)!.split(concurrency: 8, minChunk: 65_536).count, 1)
        let odd = ByteRange(start: 10, end: 100_010)!
        let parts = odd.split(concurrency: 3, minChunk: 32_768)
        XCTAssertEqual(parts.map(\.length), [33_334, 33_334, 33_333])
        XCTAssertEqual(parts.first?.start, 10)
        XCTAssertEqual(parts.last?.end, 100_010)
    }
}
