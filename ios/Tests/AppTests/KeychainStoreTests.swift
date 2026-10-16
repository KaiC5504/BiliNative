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

    func testLoadDistinguishesNotFoundFromCookies() {
        KeychainStore.deleteCookies()
        guard case .notFound = KeychainStore.load() else { return XCTFail("expected notFound") }
        XCTAssertTrue(KeychainStore.saveCookies(["SESSDATA": "abc"]))
        guard case .cookies(let cookies) = KeychainStore.load() else { return XCTFail("expected cookies") }
        XCTAssertEqual(cookies, ["SESSDATA": "abc"])
    }
}
