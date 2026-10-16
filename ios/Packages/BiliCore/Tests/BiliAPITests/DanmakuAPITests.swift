import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Danmaku
@testable import BiliAPI

final class DanmakuAPITests: XCTestCase {
    private let plainPath = "/x/v2/dm/web/seg.so"
    private let wbiPath = "/x/v2/dm/wbi/web/seg.so"
    private let navPath = "/x/web-interface/nav"
    private let spiPath = "/x/frontend/finger/spi"

    private func varint(_ value: UInt64) -> [UInt8] {
        var bytes: [UInt8] = []
        var v = value
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
        return bytes
    }

    private func field(_ number: Int, bytes: [UInt8]) -> [UInt8] {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes
    }

    private func segmentBytes(_ texts: [String], closed: Bool = false) -> Data {
        var out: [UInt8] = []
        for (i, text) in texts.enumerated() {
            let elem = varint(UInt64(2 << 3)) + varint(UInt64(1_000 * (i + 1))) + field(7, bytes: Array(text.utf8))
            out += field(1, bytes: elem)
        }
        if closed { out += varint(UInt64(2 << 3)) + varint(1) }
        return Data(out)
    }

    func testSegmentFetchSendsUnsignedQueryAndDecodes() async throws {
        let http = FakeHTTP()
        http.dataRoutes[plainPath] = (200, segmentBytes(["甲", "乙", "丙"]))
        let client = makeTestClient(http, cookies: ["SESSDATA": "s", "buvid3": "b3", "buvid4": "b4"])
        let segment = try await client.danmakuSegment(cid: 137649199, index: 2)
        XCTAssertEqual(segment.elems.map(\.content), ["甲", "乙", "丙"])
        XCTAssertFalse(segment.closed)
        let request = try XCTUnwrap(http.requests(to: plainPath).first)
        XCTAssertEqual(http.query(of: request), ["type": "1", "oid": "137649199", "segment_index": "2"])
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.headers["Referer"], BiliClient.referer)
        XCTAssertTrue(http.requests(to: wbiPath).isEmpty)
        XCTAssertTrue(http.requests(to: navPath).isEmpty)
    }

    func testSegmentFetchQueryAndWBIFallback() async throws {
        let http = FakeHTTP()
        http.routes = [plainPath: (412, ""), spiPath: (200, Fixtures.spi), navPath: (200, Fixtures.navLoggedOut)]
        http.dataRoutes[wbiPath] = (200, segmentBytes(["甲", "乙"]))
        let client = makeTestClient(http)
        let segment = try await client.danmakuSegment(cid: 55, index: 1)
        XCTAssertEqual(segment.elems.count, 2)
        let signed = try XCTUnwrap(http.requests(to: wbiPath).first)
        let query = http.query(of: signed)
        XCTAssertEqual(query["oid"], "55")
        XCTAssertEqual(query["segment_index"], "1")
        XCTAssertEqual(query["type"], "1")
        XCTAssertEqual(query["wts"], "1702204169")
        XCTAssertEqual(query["w_rid"]?.count, 32)
        XCTAssertTrue(http.query(of: try XCTUnwrap(http.requests(to: plainPath).first))["w_rid"] == nil)
    }

    func testSegmentFetchFallsBackOn403Too() async throws {
        let http = FakeHTTP()
        http.routes = [plainPath: (403, ""), navPath: (200, Fixtures.navLoggedOut)]
        http.dataRoutes[wbiPath] = (200, segmentBytes([], closed: true))
        let segment = try await makeTestClient(http).danmakuSegment(cid: 1, index: 1)
        XCTAssertTrue(segment.closed)
        XCTAssertTrue(segment.elems.isEmpty)
    }

    func testOtherHTTPErrorsAreNotRetriedOnTheSignedPath() async {
        let http = FakeHTTP()
        http.routes = [plainPath: (500, "")]
        do {
            _ = try await makeTestClient(http).danmakuSegment(cid: 1, index: 1)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(500))
        }
        XCTAssertTrue(http.requests(to: wbiPath).isEmpty)
    }

    func testFallbackFailureIsReported() async {
        let http = FakeHTTP()
        http.routes = [plainPath: (403, ""), wbiPath: (403, ""), navPath: (200, Fixtures.navLoggedOut)]
        do {
            _ = try await makeTestClient(http).danmakuSegment(cid: 1, index: 1)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(403))
        }
    }

    func testAnEmptyReplyIsAnEmptySegment() async throws {
        let http = FakeHTTP()
        http.dataRoutes[plainPath] = (200, Data())
        let segment = try await makeTestClient(http, cookies: ["buvid3": "b", "buvid4": "b"]).danmakuSegment(cid: 1, index: 1)
        XCTAssertTrue(segment.elems.isEmpty)
        XCTAssertFalse(segment.closed)
    }

    func testAnUnreadableReplyBecomesADecodingError() async {
        let http = FakeHTTP()
        http.routes = [plainPath: (200, #"{"code":-400,"message":"请求错误"}"#)]
        do {
            _ = try await makeTestClient(http, cookies: ["buvid3": "b", "buvid4": "b"]).danmakuSegment(cid: 1, index: 1)
            XCTFail("expected an error")
        } catch let error as BiliError {
            guard case .decoding = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    private let rulesPath = "/x/dm/filter/user"
    private let addPath = "/x/dm/filter/user/add"
    private let delPath = "/x/dm/filter/user/del"
    private let postPath = "/x/v2/dm/post"

    private func form(of request: HTTPRequest) -> [String: String] {
        let text = String(decoding: request.body ?? Data(), as: UTF8.self)
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            fields[String(parts[0])] = String(parts[1]).removingPercentEncoding
        }
        return fields
    }

    private func draft(gradient: Bool = false, text: String = "前方高能") -> DanmakuDraft {
        DanmakuDraft(cid: 2, bvid: "BV1GJ411x7h7", text: text, mode: 1, fontSize: 25, color: 0xFE0302,
                     gradient: gradient, progressMs: 61_500)
    }

    func testBlockRulesDecodeKinds() async throws {
        let http = FakeHTTP()
        http.routes[rulesPath] = (200, #"""
        {"code":0,"message":"0","ttl":1,"data":{"rule":[
        {"id":11,"type":0,"filter":"剧透","ctime":"2026-01-01 00:00:00"},
        {"id":12,"type":1,"filter":"/spoil.*/"},
        {"id":13,"type":2,"filter":"cbf53a1c"},
        {"id":14,"type":9,"filter":"future kind"},
        {"id":15,"type":0}],"toast":"","valid":1,"ver":3}}
        """#)
        let rules = try await makeTestClient(http, cookies: ["SESSDATA": "s", "buvid3": "b", "buvid4": "b"]).danmakuBlockRules()
        XCTAssertEqual(rules, [
            BlockRule(id: 11, kind: .keyword, filter: "剧透"),
            BlockRule(id: 12, kind: .regex, filter: "/spoil.*/"),
            BlockRule(id: 13, kind: .user, filter: "cbf53a1c"),
        ])
        XCTAssertEqual(http.requests(to: rulesPath).first?.method, "GET")
    }

    func testBlockRulesNullListIsEmpty() async throws {
        let http = FakeHTTP()
        http.routes[rulesPath] = (200, #"{"code":0,"message":"0","data":{"rule":null,"valid":0}}"#)
        let rules = try await makeTestClient(http, cookies: ["buvid3": "b", "buvid4": "b"]).danmakuBlockRules()
        XCTAssertTrue(rules.isEmpty)
    }

    func testBlockRulesLoggedOutThrowsNeedsLogin() async {
        let http = FakeHTTP()
        http.routes[rulesPath] = (200, #"{"code":-101,"message":"账号未登录"}"#)
        do {
            _ = try await makeTestClient(http, cookies: ["buvid3": "b", "buvid4": "b"]).danmakuBlockRules()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue((error as? BiliError)?.needsLogin ?? false)
        }
    }

    func testAddAndDeleteBlockRuleForms() async throws {
        let http = FakeHTTP()
        http.routes[addPath] = (200, #"{"code":0,"message":"0","data":{"id":9,"type":0,"filter":"剧透"}}"#)
        http.routes[delPath] = (200, #"{"code":0,"message":"0","data":null}"#)
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        let added = try await client.addBlockRule(.keyword, filter: "剧透")
        XCTAssertEqual(added, BlockRule(id: 9, kind: .keyword, filter: "剧透"))
        try await client.deleteBlockRule(id: 9)
        let add = try XCTUnwrap(http.requests(to: addPath).first)
        XCTAssertEqual(add.method, "POST")
        XCTAssertEqual(http.bodyText(of: add), "csrf=T&filter=%E5%89%A7%E9%80%8F&type=0")
        XCTAssertEqual(http.bodyText(of: try XCTUnwrap(http.requests(to: delPath).first)), "csrf=T&ids=9")
    }

    func testAddBlockRuleSendsTheKindsRawValueAndToleratesASparseReply() async throws {
        let http = FakeHTTP()
        http.routes[addPath] = (200, #"{"code":0,"message":"0","data":{"id":21}}"#)
        let added = try await makeTestClient(http, cookies: ["bili_jct": "T"]).addBlockRule(.user, filter: "cbf53a1c")
        XCTAssertEqual(added, BlockRule(id: 21, kind: .user, filter: "cbf53a1c"))
        XCTAssertEqual(form(of: try XCTUnwrap(http.requests(to: addPath).first))["type"], "2")
    }

    func testBlockRuleWritesNeedLoginWithoutSending() async {
        let http = FakeHTTP()
        let client = makeTestClient(http, cookies: ["SESSDATA": "s"])
        do {
            _ = try await client.addBlockRule(.keyword, filter: "x")
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue((error as? BiliError)?.needsLogin ?? false)
        }
        XCTAssertTrue(http.requests.current.isEmpty)
    }

    func testPostDanmakuForm() async throws {
        let http = FakeHTTP()
        http.routes[postPath] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"action":"","dmid":777,"dmid_str":"777"}}"#)
        let client = makeTestClient(http, cookies: ["bili_jct": "T", "SESSDATA": "s"])
        let id = try await client.postDanmaku(draft())
        XCTAssertEqual(id, 777)
        let request = try XCTUnwrap(http.requests(to: postPath).first)
        let body = http.bodyText(of: request)
        for part in ["color=16646914", "fontsize=25", "mode=1", "oid=2", "pool=0", "progress=61500", "type=1",
                     "rnd=1702204169000000", "bvid=BV1GJ411x7h7", "csrf=T"] {
            XCTAssertTrue(body.contains(part), "\(part) missing from \(body)")
        }
        XCTAssertFalse(body.contains("colorful"))
        XCTAssertEqual(form(of: request)["msg"], "前方高能")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Referer"], "https://www.bilibili.com/video/BV1GJ411x7h7")
    }

    func testPostDanmakuGradientAddsColorful() async throws {
        let http = FakeHTTP()
        http.routes[postPath] = (200, #"{"code":0,"data":{"dmid":5}}"#)
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        _ = try await client.postDanmaku(draft(gradient: true))
        XCTAssertEqual(form(of: try XCTUnwrap(http.requests(to: postPath).first))["colorful"], "60001")
    }

    func testPostDanmakuKeepsReservedCharactersAndEmoji() async throws {
        let http = FakeHTTP()
        http.routes[postPath] = (200, #"{"code":0,"data":{"dmid":5}}"#)
        let text = "a&b=c+d !'()* 😀 前方"
        _ = try await makeTestClient(http, cookies: ["bili_jct": "T"]).postDanmaku(draft(text: text))
        XCTAssertEqual(form(of: try XCTUnwrap(http.requests(to: postPath).first))["msg"], text)
    }

    func testPostDanmakuLargeIdsAndMissingIds() async throws {
        let http = FakeHTTP()
        http.routes[postPath] = (200, #"{"code":0,"data":{"dmid":1702204169000000001}}"#)
        let client = makeTestClient(http, cookies: ["bili_jct": "T"])
        let big = try await client.postDanmaku(draft())
        XCTAssertEqual(big, 1_702_204_169_000_000_001)
        http.routes[postPath] = (200, #"{"code":0,"data":{}}"#)
        let none = try await client.postDanmaku(draft())
        XCTAssertEqual(none, 0)
    }

    func testPostDanmakuServerRefusalCarriesTheMessage() async {
        let http = FakeHTTP()
        http.routes[postPath] = (200, #"{"code":36703,"message":"发送过于频繁"}"#)
        do {
            _ = try await makeTestClient(http, cookies: ["bili_jct": "T"]).postDanmaku(draft())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: 36703, message: "发送过于频繁"))
        }
    }

    func testPostDanmakuWithoutLoginSendsNothing() async {
        let http = FakeHTTP()
        do {
            _ = try await makeTestClient(http).postDanmaku(draft())
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue((error as? BiliError)?.needsLogin ?? false)
        }
        XCTAssertTrue(http.requests.current.isEmpty)
    }
}
