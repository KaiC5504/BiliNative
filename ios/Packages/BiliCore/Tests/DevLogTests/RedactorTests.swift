import XCTest
@testable import DevLog

final class RedactorTests: XCTestCase {
    func testSecretFieldsAreRedacted() {
        let out = Redactor.fields(["SESSDATA": "abc", "Cookie": "x=y", "node": "upos-sz-mirrorcosov.bilivideo.com"])
        XCTAssertEqual(out["SESSDATA"], .string("[redacted]"))
        XCTAssertEqual(out["Cookie"], .string("[redacted]"))
        XCTAssertEqual(out["node"], .string("upos-sz-mirrorcosov.bilivideo.com"))
    }

    func testSignedURLKeepsHostPathAndDeadline() {
        let url = "https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?e=ig8euxZM&uipk=5&deadline=1760000000&gen=playurlv2&os=cosovbv&upsig=deadbeef&mid=99887766"
        XCTAssertEqual(
            Redactor.text("GET \(url) done"),
            "GET https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?deadline=1760000000 done"
        )
    }

    func testCookiePairsInFreeText() {
        XCTAssertEqual(
            Redactor.text("Cookie: SESSDATA=abc%2C123; bili_jct=ff00; buvid3=keep"),
            "Cookie: SESSDATA=[redacted]; bili_jct=[redacted]; buvid3=keep"
        )
    }

    func testMidHash() {
        XCTAssertEqual(Redactor.mid(12345), Redactor.mid(12345))
        XCTAssertFalse(Redactor.mid(12345).contains("12345"))
        XCTAssertTrue(Redactor.mid(12345).hasPrefix("mid:"))
    }
}
