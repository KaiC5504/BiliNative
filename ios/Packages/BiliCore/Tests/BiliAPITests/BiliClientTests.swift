import XCTest
import BiliShared
import DevLog
@testable import BiliAPI

final class FakeHTTP: HTTPTransport, @unchecked Sendable {
    var routes: [String: (Int, String)] = [:]
    var redirects: [String: URL] = [:]
    let requests = Locked<[HTTPRequest]>([])

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.withLock { $0.append(request) }
        let key = (request.url.host ?? "") + request.url.path
        if let final = redirects[key] {
            return HTTPResponse(status: 200, headers: [:], body: Data(), finalURL: final)
        }
        guard let (status, body) = routes[request.url.path] else {
            return HTTPResponse(status: 404, headers: [:], body: Data(), finalURL: request.url)
        }
        return HTTPResponse(status: status, headers: [:], body: Data(body.utf8), finalURL: request.url)
    }

    func requests(to path: String) -> [HTTPRequest] {
        requests.current.filter { $0.url.path == path }
    }

    func query(of request: HTTPRequest) -> [String: String] {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

final class BiliClientTests: XCTestCase {
    private let navPath = "/x/web-interface/nav"
    private let viewPath = "/x/web-interface/view"
    private let playPath = "/x/player/wbi/playurl"
    private let spiPath = "/x/frontend/finger/spi"

    private func makeClient(_ http: FakeHTTP, cookies: [String: String] = [:]) -> BiliClient {
        BiliClient(transport: http, cookies: CookieJar(cookies),
                   now: { Date(timeIntervalSince1970: 1_702_204_169) }, logger: Logger(session: "test"))
    }

    func testNavDecodesLoggedOutAndKeysAreCachedForSigning() async throws {
        let http = FakeHTTP()
        http.routes = [navPath: (200, Fixtures.navLoggedOut), playPath: (200, Fixtures.playURL)]
        let client = makeClient(http)
        let nav = try await client.nav()
        XCTAssertFalse(nav.isLogin)
        _ = try await client.playURL(bvid: "BV1GJ411x7h7", cid: 1, quality: 120)
        _ = try await client.playURL(bvid: "BV1GJ411x7h7", cid: 1, quality: 120)
        XCTAssertEqual(http.requests(to: navPath).count, 1)
    }

    func testPlayURLSendsDashFlagsSignatureAndHeaders() async throws {
        let http = FakeHTTP()
        http.routes = [navPath: (200, Fixtures.navLoggedIn), playPath: (200, Fixtures.playURL)]
        let client = makeClient(http, cookies: ["SESSDATA": "abc", "buvid3": "b3"])
        let info = try await client.playURL(bvid: "BV1GJ411x7h7", cid: 137649199, quality: 120)
        XCTAssertEqual(info.dash?.video.count, 4)
        let request = try XCTUnwrap(http.requests(to: playPath).first)
        let query = http.query(of: request)
        XCTAssertEqual(query["fnval"], "4048")
        XCTAssertEqual(query["fourk"], "1")
        XCTAssertEqual(query["qn"], "120")
        XCTAssertEqual(query["wts"], "1702204169")
        XCTAssertEqual(query["w_rid"]?.count, 32)
        XCTAssertEqual(request.headers["Referer"], "https://www.bilibili.com/")
        XCTAssertEqual(request.headers["User-Agent"], BiliClient.userAgent)
        XCTAssertEqual(request.headers["Cookie"], "SESSDATA=abc; buvid3=b3")
    }

    func testEnsureRiskCookiesFetchesOnlyWhenMissing() async throws {
        let http = FakeHTTP()
        http.routes = [spiPath: (200, Fixtures.spi)]
        let client = makeClient(http)
        try await client.ensureRiskCookies()
        XCTAssertEqual(client.cookies.value("buvid3"), "B3-VALUE-infoc")
        XCTAssertEqual(client.cookies.value("buvid4"), "B4-VALUE")
        try await client.ensureRiskCookies()
        XCTAssertEqual(http.requests(to: spiPath).count, 1)
    }

    func testAPIErrorCodeThrows() async {
        let http = FakeHTTP()
        http.routes = [viewPath: (200, Fixtures.notFound)]
        do {
            _ = try await makeClient(http).view(bvid: "BV1GJ411x7h7")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: -404, message: "啥都木有"))
            XCTAssertEqual((error as? BiliError)?.userMessage, "视频不存在或已被删除")
        }
    }

    func testDurlOnlyThrowsNotDash() async {
        let http = FakeHTTP()
        http.routes = [navPath: (200, Fixtures.navLoggedIn), playPath: (200, Fixtures.durlOnly)]
        do {
            _ = try await makeClient(http).playURL(bvid: "BV1GJ411x7h7", cid: 1, quality: 80)
            XCTFail("expected notDash")
        } catch {
            XCTAssertEqual(error as? BiliError, .notDash)
            XCTAssertEqual((error as? BiliError)?.userMessage, "这个视频不是 DASH 格式，暂不支持")
        }
    }

    func testRiskControlIsRetriedOnceWithFreshCookies() async {
        let http = FakeHTTP()
        http.routes = [viewPath: (412, ""), spiPath: (200, Fixtures.spi)]
        let client = makeClient(http, cookies: ["buvid3": "old", "buvid4": "old"])
        do {
            _ = try await client.view(bvid: "BV1GJ411x7h7")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(412))
        }
        XCTAssertEqual(http.requests(to: viewPath).count, 2)
        XCTAssertEqual(http.requests(to: spiPath).count, 1)
        XCTAssertEqual(client.cookies.value("buvid3"), "B3-VALUE-infoc")
    }

    func testResolveShortLinkFollowsRedirect() async throws {
        let http = FakeHTTP()
        http.routes = [viewPath: (200, Fixtures.view)]
        http.redirects["b23.tv/xyZ123a"] = URL(string: "https://www.bilibili.com/video/BV1GJ411x7h7?p=2&share_source=copy")!
        let (view, page) = try await makeClient(http).resolve(.short(URL(string: "https://b23.tv/xyZ123a")!))
        XCTAssertEqual(view.bvid, "BV1GJ411x7h7")
        XCTAssertEqual(page, 2)
        XCTAssertEqual(http.query(of: try XCTUnwrap(http.requests(to: viewPath).first))["bvid"], "BV1GJ411x7h7")
    }

    func testResolveRequestsPlainHTTPShortLinkOverHTTPS() async throws {
        let http = FakeHTTP()
        http.routes = [viewPath: (200, Fixtures.view)]
        http.redirects["b23.tv/xyZ123a"] = URL(string: "https://www.bilibili.com/video/BV1GJ411x7h7")!
        _ = try await makeClient(http).resolve(.short(URL(string: "http://b23.tv/xyZ123a")!))
        let first = try XCTUnwrap(http.requests.current.first)
        XCTAssertEqual(first.url.scheme, "https")
        XCTAssertEqual(first.url.host, "b23.tv")
        XCTAssertNil(first.headers["Cookie"])
    }

    func testEmptyWBIKeysFailInsteadOfSigningWithABadKey() async {
        let http = FakeHTTP()
        let emptyKeys = #"{"code":-101,"message":"账号未登录","data":{"isLogin":false,"wbi_img":{"img_url":"","sub_url":""}}}"#
        http.routes = [navPath: (200, emptyKeys), playPath: (200, Fixtures.playURL)]
        do {
            _ = try await makeClient(http).playURL(bvid: "BV1GJ411x7h7", cid: 1, quality: 80)
            XCTFail("expected a decoding error")
        } catch {
            guard case .decoding = error as? BiliError else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertTrue(http.requests(to: playPath).isEmpty)
    }

    func testCookieJarHeaderAndParse() {
        let jar = CookieJar(CookieJar.parse(header: "SESSDATA=abc; buvid3=x=y; empty"))
        XCTAssertEqual(jar.value("buvid3"), "x=y")
        XCTAssertEqual(jar.headerValue, "SESSDATA=abc; buvid3=x=y")
        let changes = Locked(0)
        jar.onChange = { _ in changes.withLock { $0 += 1 } }
        jar.set("bili_jct", "z")
        jar.removeAll()
        XCTAssertEqual(changes.current, 2)
        XCTAssertNil(jar.headerValue)
    }
}
