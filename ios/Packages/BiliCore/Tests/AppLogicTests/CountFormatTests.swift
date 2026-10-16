import XCTest
@testable import AppLogic

final class CountFormatTests: XCTestCase {
    func testShortCounts() {
        XCTAssertEqual(CountFormat.short(0), "0")
        XCTAssertEqual(CountFormat.short(9131), "9131")
        XCTAssertEqual(CountFormat.short(9999), "9999")
        XCTAssertEqual(CountFormat.short(10_000), "1万")
        XCTAssertEqual(CountFormat.short(37_000), "3.7万")
        XCTAssertEqual(CountFormat.short(82_838_000), "8283.8万")
        XCTAssertEqual(CountFormat.short(120_000_000), "1.2亿")
        XCTAssertEqual(CountFormat.short(100_000_000), "1亿")
    }

    func testShortCountsTruncateInsteadOfRoundingUp() {
        XCTAssertEqual(CountFormat.short(10_999), "1万")
        XCTAssertEqual(CountFormat.short(99_999_999), "9999.9万")
        XCTAssertEqual(CountFormat.short(199_999_999), "1.9亿")
    }
}
