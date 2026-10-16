import XCTest
@testable import BiliNative

final class KeychainStoreTests: XCTestCase {
    override func tearDown() {
        KeychainStore.deleteCookies()
    }

    func testRoundTripAndDelete() {
        XCTAssertTrue(KeychainStore.saveCookies(["SESSDATA": "abc", "bili_jct": "def"]))
        XCTAssertEqual(KeychainStore.loadCookies(), ["SESSDATA": "abc", "bili_jct": "def"])
        XCTAssertTrue(KeychainStore.saveCookies(["SESSDATA": "new"]))
        XCTAssertEqual(KeychainStore.loadCookies(), ["SESSDATA": "new"])
        KeychainStore.deleteCookies()
        XCTAssertEqual(KeychainStore.loadCookies(), [:])
    }
}
