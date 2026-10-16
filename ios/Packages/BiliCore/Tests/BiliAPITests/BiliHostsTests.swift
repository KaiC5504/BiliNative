import XCTest
@testable import BiliAPI

final class BiliHostsTests: XCTestCase {
    func testAcceptsBilibiliAndSubdomains() {
        for host in [".bilibili.com", "bilibili.com", "www.bilibili.com", "BILIBILI.COM", ".Passport.Bilibili.com"] {
            XCTAssertTrue(BiliHosts.isBilibili(host), host)
        }
    }

    func testRejectsLookalikes() {
        for host in ["evilbilibili.com", "bilibili.com.evil.com", "notbilibili.com", "", ".", "bilibili.co"] {
            XCTAssertFalse(BiliHosts.isBilibili(host), host)
        }
    }
}
