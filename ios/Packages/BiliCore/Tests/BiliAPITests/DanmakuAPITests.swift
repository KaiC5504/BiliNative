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
}
