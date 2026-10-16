import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BiliAPI

final class AppSignerTests: XCTestCase {
    private let authCodePath = "/x/passport-tv-login/qrcode/auth_code"
    private let pollPath = "/x/passport-tv-login/qrcode/poll"
    private let dislikePath = "/x/v2/view/dislike"
    private let spiPath = "/x/frontend/finger/spi"
    private let signer = AppSigner(appKey: "testkey", appSecret: "testsecret")
    // The clock makeTestClient fixes.
    private let ts = "1702204169"

    private func makeClient(_ http: FakeHTTP) -> BiliClient {
        makeTestClient(http, cookies: ["SESSDATA": "sess", "bili_jct": "TOKEN", "buvid3": "b3"])
    }

    private func fields(of request: HTTPRequest, _ http: FakeHTTP) -> [String: String] {
        let body = http.bodyText(of: request)
        let pairs = body.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        return Dictionary(pairs.map { ($0[0], $0.count > 1 ? $0[1] : "") }, uniquingKeysWith: { first, _ in first })
    }

    func testSignerMatchesTheDocumentedAlgorithm() {
        let signed = AppSigner(appKey: "testkey", appSecret: "testsecret").signed(["b": "你好", "a": "1"], ts: 100)
        XCTAssertEqual(signed["sign"], "a650ecac0ce853a58e81f3366d428dbb")   // md5("a=1&appkey=testkey&b=%E4%BD%A0%E5%A5%BD&ts=100" + "testsecret")
        XCTAssertEqual(signed["appkey"], "testkey"); XCTAssertEqual(signed["ts"], "100")
    }

    func testSignerKeepsTheCallersFieldsAndIsDeterministic() {
        let signed = signer.signed(["aid": "1"], ts: 5)
        XCTAssertEqual(signed["aid"], "1")
        XCTAssertEqual(Set(signed.keys), ["aid", "appkey", "ts", "sign"])
        XCTAssertEqual(signer.signed(["aid": "1"], ts: 5), signed)
        XCTAssertNotEqual(signer.signed(["aid": "1"], ts: 6)["sign"], signed["sign"])
    }

    func testTVAuthCodePostsASignedFormWithoutCSRFOrCookies() async throws {
        let http = FakeHTTP()
        http.routes[authCodePath] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"url":"https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1","auth_code":"AUTH1"}}"#)
        let code = try await makeClient(http).tvAuthCode(signer: signer)
        XCTAssertEqual(code.url, "https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1")
        XCTAssertEqual(code.authCode, "AUTH1")
        let request = try XCTUnwrap(http.requests(to: authCodePath).first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://passport.bilibili.com" + authCodePath)
        XCTAssertEqual(http.bodyText(of: request), "appkey=testkey&local_id=0&sign=0e70305826df54da099eb970792b17cd&ts=\(ts)")
        XCTAssertNil(request.headers["Cookie"])
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded; charset=UTF-8")
    }

    func testTVAuthCodeErrorThrows() async {
        let http = FakeHTTP()
        http.routes[authCodePath] = (200, #"{"code":-400,"message":"请求错误"}"#)
        do {
            _ = try await makeClient(http).tvAuthCode(signer: signer)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: -400, message: "请求错误"))
        }
    }

    func testTVPollSignsTheAuthCode() async throws {
        let http = FakeHTTP()
        http.routes[pollPath] = (200, #"{"code":86039,"message":"二维码尚未确认","ttl":1,"data":null}"#)
        _ = try await makeClient(http).tvPoll(signer: signer, authCode: "AUTH1")
        let request = try XCTUnwrap(http.requests(to: pollPath).first)
        XCTAssertEqual(request.url.absoluteString, "https://passport.bilibili.com" + pollPath)
        XCTAssertEqual(http.bodyText(of: request), "appkey=testkey&auth_code=AUTH1&local_id=0&sign=7f3e83052d4dd9bf44e1a52cde734a9c&ts=\(ts)")
        XCTAssertNil(request.headers["Cookie"])
    }

    func testTVPollStates() async throws {
        let http = FakeHTTP()
        let client = makeClient(http)
        func poll(_ reply: String) async throws -> TVLoginState {
            http.routes[pollPath] = (200, reply)
            return try await client.tvPoll(signer: signer, authCode: "AUTH1")
        }
        let waiting = try await poll(#"{"code":86039,"message":"二维码尚未确认","data":null}"#)
        XCTAssertEqual(waiting, .waiting)
        let scanned = try await poll(#"{"code":86090,"message":"二维码已扫码未确认","data":null}"#)
        XCTAssertEqual(scanned, .waiting)
        let expired = try await poll(#"{"code":86038,"message":"二维码已失效","data":null}"#)
        XCTAssertEqual(expired, .expired)
        let confirmed = try await poll(#"{"code":0,"message":"0","ttl":1,"data":{"mid":12345,"access_token":"ACCESS-TOKEN","refresh_token":"REFRESH","expires_in":15551999,"cookie_info":{"cookies":[]},"sso":[]}}"#)
        XCTAssertEqual(confirmed, .confirmed(accessToken: "ACCESS-TOKEN", mid: 12345))
    }

    func testTVPollOtherCodesAndTokenlessSuccessThrow() async {
        let http = FakeHTTP()
        let client = makeClient(http)
        http.routes[pollPath] = (200, #"{"code":-3,"message":"API校验密匙错误","data":null}"#)
        do {
            _ = try await client.tvPoll(signer: signer, authCode: "AUTH1")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: -3, message: "API校验密匙错误"))
        }
        for reply in [#"{"code":0,"message":"0","data":null}"#, #"{"code":0,"message":"0","data":{"mid":1}}"#,
                      #"{"code":0,"message":"0","data":{"access_token":"","mid":1}}"#] {
            http.routes[pollPath] = (200, reply)
            do {
                _ = try await client.tvPoll(signer: signer, authCode: "AUTH1")
                XCTFail("expected an error for \(reply)")
            } catch {
                guard case .decoding = error as? BiliError else { return XCTFail("\(error)") }
            }
        }
    }

    func testDislikeSendsNoCookiesAndNoCSRF() async throws {
        let http = FakeHTTP()
        http.routes[dislikePath] = (200, #"{"code":0,"message":"0","ttl":1,"data":null}"#)
        let client = makeClient(http)
        try await client.dislike(aid: 80433022, on: true, accessToken: "tok/en", signer: signer)
        let request = try XCTUnwrap(http.requests(to: dislikePath).first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://app.bilibili.com" + dislikePath)
        XCTAssertNil(request.headers["Cookie"])
        XCTAssertNil(request.headers["Origin"])
        let body = http.bodyText(of: request)
        XCTAssertEqual(body, "access_key=tok%2Fen&aid=80433022&appkey=testkey&dislike=0&sign=a31c3355ac92c79564a32c276628db02&ts=\(ts)")
        XCTAssertFalse(body.contains("csrf"))
        XCTAssertFalse(body.contains("TOKEN"))

        try await client.dislike(aid: 80433022, on: false, accessToken: "tok/en", signer: signer)
        let undo = try XCTUnwrap(http.requests(to: dislikePath).last)
        XCTAssertEqual(fields(of: undo, http)["dislike"], "1")
        XCTAssertEqual(fields(of: undo, http)["sign"], "4dbe03ff280d7bd7726a96a72092f02f")
    }

    func testDislikeFailuresThrow() async {
        let http = FakeHTTP()
        let client = makeClient(http)
        http.routes[dislikePath] = (200, #"{"code":-101,"message":"账号未登录"}"#)
        do {
            try await client.dislike(aid: 1, on: true, accessToken: "t", signer: signer)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: -101, message: "账号未登录"))
        }
        http.routes[dislikePath] = (200, "<html>nope</html>")
        do {
            try await client.dislike(aid: 1, on: true, accessToken: "t", signer: signer)
            XCTFail("expected an error")
        } catch {
            guard case .decoding = error as? BiliError else { return XCTFail("\(error)") }
        }
    }

    func testCookielessRequestIsNotRetriedOnRisk412() async {
        let http = FakeHTTP()
        http.routes = [dislikePath: (412, ""), spiPath: (200, Fixtures.spi)]
        do {
            try await makeClient(http).dislike(aid: 1, on: true, accessToken: "t", signer: signer)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(412))
        }
        XCTAssertEqual(http.requests(to: dislikePath).count, 1)
        XCTAssertTrue(http.requests(to: spiPath).isEmpty)
    }
}
