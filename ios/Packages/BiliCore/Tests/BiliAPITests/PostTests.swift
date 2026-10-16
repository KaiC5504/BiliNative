import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BiliAPI

final class PostTests: XCTestCase {
    private let togglePath = "/x/v2/history/toview/add"
    private let spiPath = "/x/frontend/finger/spi"
    private let okEmpty = #"{"code":0,"message":"0","data":null}"#

    func testPostSendsFormWithCSRFAndBrowserHeaders() async throws {
        let http = FakeHTTP()
        http.routes[togglePath] = (200, okEmpty)
        let client = makeTestClient(http, cookies: ["bili_jct": "TOKEN", "SESSDATA": "s"])
        try await client.post(togglePath, form: ["aid": "1"], referer: "https://www.bilibili.com/video/BV1")
        let request = try XCTUnwrap(http.requests(to: togglePath).first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request), "aid=1&csrf=TOKEN")
        XCTAssertEqual(request.headers["Origin"], "https://www.bilibili.com")
        XCTAssertEqual(request.headers["Referer"], "https://www.bilibili.com/video/BV1")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded; charset=UTF-8")
        XCTAssertEqual(request.headers["User-Agent"], BiliClient.userAgent)
        XCTAssertEqual(request.headers["Cookie"], "SESSDATA=s; bili_jct=TOKEN")
        XCTAssertEqual(request.url.absoluteString, "https://api.bilibili.com" + togglePath)
    }

    func testPostRefererDefaultsToTheSiteRoot() async throws {
        let http = FakeHTTP()
        http.routes[togglePath] = (200, okEmpty)
        try await makeTestClient(http, cookies: ["bili_jct": "T"]).post(togglePath, form: [:])
        XCTAssertEqual(http.requests(to: togglePath).first?.headers["Referer"], BiliClient.referer)
    }

    func testPostOverridesACallerSuppliedCSRF() async throws {
        let http = FakeHTTP()
        http.routes[togglePath] = (200, okEmpty)
        try await makeTestClient(http, cookies: ["bili_jct": "REAL"]).post(togglePath, form: ["csrf": "forged", "aid": "1"])
        XCTAssertEqual(http.bodyText(of: try XCTUnwrap(http.requests(to: togglePath).first)), "aid=1&csrf=REAL")
    }

    func testPostWithoutCSRFCookieThrowsWithoutSending() async {
        let http = FakeHTTP()
        let client = makeTestClient(http, cookies: ["SESSDATA": "s"])
        do {
            try await client.post(togglePath, form: ["aid": "1"])
            XCTFail("expected -101")
        } catch let error as BiliError {
            XCTAssertTrue(error.needsLogin)
            XCTAssertEqual(error, .api(code: -101, message: "账号未登录"))
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertTrue(http.requests.current.isEmpty)
    }

    func testRiskControlCodesReadAsTooFrequent() {
        XCTAssertEqual(BiliError.api(code: -352, message: "").userMessage, "请求过于频繁，请稍后再试")
        XCTAssertEqual(BiliError.api(code: -412, message: "").userMessage, "请求过于频繁，请稍后再试")
        XCTAssertEqual(BiliError.api(code: -101, message: "").userMessage, "需要登录")
    }

    func testNeedsLoginIsOnlyForCode101() {
        XCTAssertTrue(BiliError.api(code: -101, message: "x").needsLogin)
        XCTAssertFalse(BiliError.api(code: -352, message: "x").needsLogin)
        XCTAssertFalse(BiliError.http(401).needsLogin)
    }

    func testPostErrorCodeThrowsTheServerMessage() async {
        let http = FakeHTTP()
        http.routes[togglePath] = (200, #"{"code":34002,"message":"不能给自己点赞"}"#)
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        do {
            try await client.post(togglePath, form: [:])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: 34002, message: "不能给自己点赞"))
        }
    }

    func testPostDecodesTheDataOnSuccess() async throws {
        struct Result: Decodable, Equatable { let like: Bool }
        let http = FakeHTTP()
        http.routes["POST /x/web-interface/archive/like"] = (200, #"{"code":0,"message":"0","data":{"like":true}}"#)
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        let result: Result = try await client.post("/x/web-interface/archive/like", form: ["bvid": "BV1"])
        XCTAssertEqual(result, Result(like: true))
    }

    func testPostThatExpectsDataThrowsWhenSuccessCarriesNone() async {
        struct Result: Decodable { let like: Bool }
        let http = FakeHTTP()
        http.routes[togglePath] = (200, okEmpty)
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        do {
            let _: Result = try await client.post(togglePath, form: [:])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: 0, message: "0"))
        }
    }

    func testPostHTTPFailureThrows() async {
        let http = FakeHTTP()
        http.routes[togglePath] = (500, "")
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        do {
            try await client.post(togglePath, form: [:])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(500))
        }
    }

    func testPostRisk412IsRetriedOnceWithTheSameForm() async {
        let http = FakeHTTP()
        http.routes = [togglePath: (412, ""), spiPath: (200, Fixtures.spi)]
        let client = makeTestClient(http, cookies: ["bili_jct": "T", "buvid3": "old", "buvid4": "old"])
        do {
            try await client.post(togglePath, form: ["aid": "1"])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(412))
        }
        let sent = http.requests(to: togglePath)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.map { http.bodyText(of: $0) }, ["aid=1&csrf=T", "aid=1&csrf=T"])
        XCTAssertEqual(sent.last?.headers["Cookie"]?.contains("buvid3=B3-VALUE-infoc"), true)
    }

    func testRoutesCanAnswerOneMethodOnly() async throws {
        struct V: Decodable { let v: String }
        let http = FakeHTTP()
        http.routes["POST /p"] = (200, #"{"code":0,"data":{"v":"post"}}"#)
        http.routes["/p"] = (200, #"{"code":0,"data":{"v":"any"}}"#)
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        let posted: V = try await client.post("/p", form: [:])
        let fetched: V = try await client.get("/p", query: [:], signed: false)
        XCTAssertEqual(posted.v, "post")
        XCTAssertEqual(fetched.v, "any")
    }

    func testFormEncodingKeepsReservedCharactersAndEmoji() {
        let body = String(decoding: FormEncoding.encode(["message": "a&b=c+d !'()* 你好😀", "b": "1"]), as: UTF8.self)
        XCTAssertEqual(body, "b=1&message=a%26b%3Dc%2Bd%20%21%27%28%29%2A%20%E4%BD%A0%E5%A5%BD%F0%9F%98%80")
    }

    func testFormEncodingEncodesKeysAndHandlesEmptyForm() {
        XCTAssertEqual(String(decoding: FormEncoding.encode([:]), as: UTF8.self), "")
        XCTAssertEqual(String(decoding: FormEncoding.encode(["a b": "~-._"]), as: UTF8.self), "a%20b=~-._")
    }

    func testGetDataReturnsTheRawBodyAndHostCanChange() async throws {
        struct N: Decodable { let n: Int }
        let http = FakeHTTP()
        http.dataRoutes["/x/v2/dm/web/seg.so"] = (200, Data([0x08, 0x01, 0xff, 0x80]))
        let client = makeTestClient(http, cookies: ["SESSDATA": "s"])
        let data = try await client.getData("/x/v2/dm/web/seg.so", query: ["oid": "1", "type": "1"], signed: false)
        XCTAssertEqual(data, Data([0x08, 0x01, 0xff, 0x80]))
        let request = try XCTUnwrap(http.requests(to: "/x/v2/dm/web/seg.so").first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertNil(request.body)
        XCTAssertEqual(http.query(of: request), ["oid": "1", "type": "1"])

        http.routes["/ok"] = (200, #"{"code":0,"data":{"n":1}}"#)
        let _: N = try await client.get("/ok", query: [:], signed: false, host: "https://account.bilibili.com")
        XCTAssertEqual(http.requests(to: "/ok").first?.url.host, "account.bilibili.com")
    }

    func testGetDataHTTPFailureThrows() async {
        let http = FakeHTTP()
        do {
            _ = try await makeTestClient(http).getData("/missing", query: [:], signed: false)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(404))
        }
    }

    func testGetDataRisk412IsRetriedOnce() async {
        let http = FakeHTTP()
        http.routes = ["/seg": (412, ""), spiPath: (200, Fixtures.spi)]
        do {
            _ = try await makeTestClient(http).getData("/seg", query: [:], signed: false)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(412))
        }
        XCTAssertEqual(http.requests(to: "/seg").count, 2)
    }

    func testCookiesAreNotSentToANonBilibiliHost() async throws {
        struct N: Decodable { let n: Int }
        let http = FakeHTTP()
        http.routes["/ok"] = (200, #"{"code":0,"data":{"n":1}}"#)
        let client = makeTestClient(http, cookies: ["SESSDATA": "s", "bili_jct": "T"])
        let _: N = try await client.get("/ok", query: [:], signed: false, host: "https://evil.example")
        XCTAssertNil(http.requests(to: "/ok").first?.headers["Cookie"])
    }

    func testPostToANonBilibiliHostIsRefusedWithoutSending() async {
        let http = FakeHTTP()
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        do {
            try await client.post("/ok", form: [:], host: "https://evil.example")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .invalidLink)
        }
        XCTAssertTrue(http.requests.current.isEmpty)
    }
}
