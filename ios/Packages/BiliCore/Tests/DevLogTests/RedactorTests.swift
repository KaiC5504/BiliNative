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
            "Cookie: SESSDATA=[redacted]; bili_jct=[redacted]; buvid3=[redacted]"
        )
    }

    func testAuthorizationHeaderInFreeText() {
        XCTAssertEqual(Redactor.text("Authorization: Bearer TOPSECRET"), "Authorization: [redacted]")
        XCTAssertEqual(Redactor.text("sent authorization: Basic dXNlcjpwdw== ok"), "sent authorization: [redacted]")
        XCTAssertEqual(Redactor.text("AUTHORIZATION: rawtoken123"), "AUTHORIZATION: [redacted]")
        XCTAssertEqual(Redactor.text(#"{"Authorization":"Bearer abc"}"#), #"{"Authorization":"[redacted]"}"#)
    }

    func testCookieAndSetCookieHeadersKeepNamesOnly() {
        XCTAssertEqual(Redactor.text("Cookie: foo=bar; buvid3=keep"), "Cookie: foo=[redacted]; buvid3=[redacted]")
        XCTAssertEqual(
            Redactor.text("Set-Cookie: SESSDATA=abc; Path=/; HttpOnly; Secure"),
            "Set-Cookie: SESSDATA=[redacted]; Path=[redacted]; HttpOnly; Secure"
        )
        XCTAssertEqual(Redactor.text("set-cookie: sid=zzz"), "set-cookie: sid=[redacted]")
    }

    func testSecretFieldKeysAreMatchedLooselyAndCaseInsensitively() {
        let out = Redactor.fields([
            "X-CSRF-Token": "t", "csrf_token": "t", "Set-Cookie": "a=b", "AUTHORIZATION": "Bearer x",
            "Access_Key": "k", "bili_jct": "j", "ok": "fine",
        ])
        for key in ["X-CSRF-Token", "csrf_token", "Set-Cookie", "AUTHORIZATION", "Access_Key", "bili_jct"] {
            XCTAssertEqual(out[key], .string("[redacted]"), key)
        }
        XCTAssertEqual(out["ok"], .string("fine"))
    }

    func testMidAndDedeUserIDFieldsAreHashed() {
        let out = Redactor.fields(["mid": 99887766, "DedeUserID": "99887766", "Mid": .string("mid:abcd1234")])
        XCTAssertEqual(out["mid"], .string(Redactor.mid(99887766)))
        XCTAssertEqual(out["DedeUserID"], .string(Redactor.mid(99887766)))
        XCTAssertEqual(out["Mid"], .string("mid:abcd1234"))
        XCTAssertFalse(String(describing: out).contains("99887766"))
    }

    func testCSRFPairsAnywhereInFreeText() {
        XCTAssertEqual(Redactor.text("x-csrf-token=abc bili_jct=ff"), "x-csrf-token=[redacted] bili_jct=[redacted]")
        XCTAssertEqual(Redactor.text("body csrf_token=abc&csrf=def end"), "body csrf_token=[redacted]&csrf=[redacted] end")
        XCTAssertEqual(Redactor.text("X-CSRF-Token: abc123"), "X-CSRF-Token: [redacted]")
    }

    func testURLRegexKeepsTrailingPunctuation() {
        let signed = "https://h.bilivideo.com/p/a.m4s?deadline=1&upsig=S"
        let kept = "https://h.bilivideo.com/p/a.m4s?deadline=1"
        XCTAssertEqual(Redactor.text("(\(signed)), then \(signed)."), "(\(kept)), then \(kept).")
        XCTAssertEqual(Redactor.text("a \(signed); b \(signed)\"c"), "a \(kept); b \(kept)\"c")
    }

    func testUnparseableURLNeverKeepsItsQuery() {
        XCTAssertEqual(Redactor.url("not a url?upsig=S#f"), "not a url")
    }

    func testURLWithoutDeadlineLosesQuery() {
        XCTAssertEqual(Redactor.text("https://api.bilibili.com/x?csrf=abc&access_key=zzz#f"), "https://api.bilibili.com/x")
    }

    func testMidHash() {
        XCTAssertEqual(Redactor.mid(12345), Redactor.mid(12345))
        XCTAssertFalse(Redactor.mid(12345).contains("12345"))
        XCTAssertTrue(Redactor.mid(12345).hasPrefix("mid:"))
    }
}
