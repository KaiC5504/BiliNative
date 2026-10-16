import XCTest
@testable import BiliNative

@MainActor
final class AppTokenStoreTests: XCTestCase {
    override func tearDown() {
        AppTokenStore.delete()
    }

    func testRoundTripAndDelete() {
        AppTokenStore.delete()
        XCTAssertNil(AppTokenStore.load())
        XCTAssertTrue(AppTokenStore.save("token-one"))
        XCTAssertEqual(AppTokenStore.load(), "token-one")
        XCTAssertTrue(AppTokenStore.save("token-two"))
        XCTAssertEqual(AppTokenStore.load(), "token-two")
        AppTokenStore.delete()
        XCTAssertNil(AppTokenStore.load())
    }

    func testSavingAnEmptyTokenClearsIt() {
        XCTAssertTrue(AppTokenStore.save("token-one"))
        XCTAssertTrue(AppTokenStore.save(""))
        XCTAssertNil(AppTokenStore.load())
    }

    func testTheTokenAndTheCookiesDoNotShareAnItem() {
        XCTAssertTrue(KeychainStore.saveCookies(["SESSDATA": "abc"]))
        defer { KeychainStore.deleteCookies() }
        XCTAssertTrue(AppTokenStore.save("token-one"))
        AppTokenStore.delete()
        XCTAssertEqual(KeychainStore.loadCookies(), ["SESSDATA": "abc"])
    }

    func testLogoutClearsTheToken() async {
        XCTAssertTrue(AppTokenStore.save("token-one"))
        await AppEnvironment().logout()
        // The Keychain writes go through a background queue that logout does not wait for.
        let deadline = Date().addingTimeInterval(5)
        while AppTokenStore.load() != nil && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(AppTokenStore.load())
    }
}
