import XCTest
import BiliShared
import DevLog
@testable import BiliAPI

final class FeedAPITests: XCTestCase {
    private let navPath = "/x/web-interface/nav"
    private let feedPath = "/x/web-interface/wbi/index/top/feed/rcmd"
    private let historyPath = "/x/web-interface/history/cursor"

    private var fakeHTTP: FakeHTTP!
    private var client: BiliClient!

    override func setUp() {
        fakeHTTP = FakeHTTP()
        fakeHTTP.routes[navPath] = (200, Fixtures.navLoggedIn)
        client = makeTestClient(fakeHTTP, cookies: ["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"])
    }

    // The web feed names the aid `id` and carries no `dimension`; the vertical and rotated rows are invented to cover the shape rule.
    private let feed = #"""
    {"code":0,"message":"OK","ttl":1,"data":{"item":[
    {"id":0,"goto":"ad","bvid":"","cid":0,"title":"广告位","pic":"https://i0.hdslb.com/bfs/archive/ad-0001.jpg","owner":{"mid":0,"name":""},"stat":{"view":0,"danmaku":0}},
    {"id":91000001,"bvid":"BV1AA411a1aA","cid":138000001,"goto":"av","uri":"https://www.bilibili.com/video/BV1AA411a1aA","pic":"http://i0.hdslb.com/bfs/archive/feed-0001.jpg","title":"推荐视频一","duration":79,"pubdate":1760000000,
    "owner":{"mid":501,"name":"UP主甲","face":"https://i0.hdslb.com/bfs/face/face-0501.jpg"},"stat":{"view":347398,"like":19093,"danmaku":631,"vt":0},"is_followed":0,
    "rcmd_reason":{"content":"2万点赞","reason_type":3},"track_id":"web_pegasus_0.test"},
    {"id":5001,"goto":"live","bvid":"","title":"直播间","pic":"https://i0.hdslb.com/bfs/live/live-0001.jpg","owner":{"mid":502,"name":"主播"},"stat":{"view":10,"danmaku":0}},
    {"id":91000002,"bvid":"BV1BB411b2bB","cid":138000002,"goto":"av","pic":"https://i0.hdslb.com/bfs/archive/feed-0002.jpg","title":"竖屏视频","duration":15,"pubdate":1760000100,
    "owner":{"mid":503,"name":"UP主乙"},"stat":{"view":"--","danmaku":7},"rcmd_reason":{"reason_type":0},"dimension":{"width":1080,"height":1920,"rotate":0}},
    {"id":91000003,"bvid":"BV1CC411c3cC","cid":138000003,"goto":"av","pic":"https://i0.hdslb.com/bfs/archive/feed-0003.jpg","title":"存成竖的横屏视频","duration":300,"pubdate":1760000200,
    "owner":{"mid":504,"name":"UP主丙"},"stat":{"view":42,"danmaku":1},"rcmd_reason":null,"dimension":{"width":1080,"height":1920,"rotate":1}},
    {"id":91000004,"bvid":"","goto":"av","pic":"","title":"没有BV号","owner":{"mid":1,"name":"x"},"stat":{"view":1,"danmaku":1}}
    ]}}
    """#

    func testFeedKeepsOnlyVideosAndReadsReasonAndShape() async throws {
        fakeHTTP.routes[feedPath] = (200, feed)
        let cards = try await client.recommendFeed(index: 1)
        XCTAssertEqual(cards.map(\.bvid), ["BV1AA411a1aA", "BV1BB411b2bB", "BV1CC411c3cC"])
        XCTAssertEqual(cards[0], FeedCard(
            aid: 91000001, bvid: "BV1AA411a1aA", cid: 138000001, title: "推荐视频一",
            cover: "http://i0.hdslb.com/bfs/archive/feed-0001.jpg", duration: 79, views: 347398, danmaku: 631,
            ownerName: "UP主甲", ownerMid: 501, reason: "2万点赞", isVertical: false))
        XCTAssertEqual(cards[0].id, "BV1AA411a1aA")
        XCTAssertNil(cards[1].reason)
        XCTAssertNil(cards[2].reason)
        XCTAssertEqual(cards.map(\.isVertical), [false, true, false])
        XCTAssertEqual(cards[1].views, 0)
        XCTAssertEqual(cards[1].ownerMid, 503)
    }

    func testFeedQuery() async throws {
        fakeHTTP.routes[feedPath] = (200, feed)
        _ = try await client.recommendFeed(index: 3)
        let request = try XCTUnwrap(fakeHTTP.requests(to: feedPath).first)
        let query = fakeHTTP.query(of: request)
        XCTAssertEqual(query["fresh_type"], "4")
        XCTAssertEqual(query["ps"], "12")
        XCTAssertEqual(query["fresh_idx"], "3")
        XCTAssertEqual(query["fresh_idx_1h"], "3")
        XCTAssertEqual(query["brush"], "3")
        XCTAssertEqual(query["feed_version"], "V8")
        XCTAssertNotNil(query["w_rid"])
        XCTAssertNotNil(query["wts"])
    }

    func testFeedWithoutItemsIsEmpty() async throws {
        fakeHTTP.routes[feedPath] = (200, #"{"code":0,"message":"OK","ttl":1,"data":{"item":null}}"#)
        let none = try await client.recommendFeed(index: 1)
        XCTAssertEqual(none, [])
        fakeHTTP.routes[feedPath] = (200, #"{"code":0,"message":"OK","ttl":1,"data":null}"#)
        let nothing = try await client.recommendFeed(index: 2)
        XCTAssertEqual(nothing, [])
    }

    private let firstHistoryPage = #"""
    {"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":90000003,"view_at":1760600000,"business":"archive","ps":20},"tab":[{"type":"archive","name":"视频"}],"list":[
    {"title":"历史视频一","long_title":"","cover":"https://i0.hdslb.com/bfs/archive/his-0001.jpg","covers":null,"uri":"",
    "history":{"oid":90000001,"epid":0,"bvid":"BV1HA411a1aA","page":2,"cid":137650101,"part":"第二集","business":"archive","dt":1},
    "videos":2,"author_name":"UP主甲","author_face":"https://i0.hdslb.com/bfs/face/face-0511.jpg","author_mid":511,"view_at":1760700000,"progress":65,"badge":"","show_title":"","duration":212,"is_fav":0,"kid":90000001,"live_status":0},
    {"title":"历史视频二","cover":"https://i0.hdslb.com/bfs/archive/his-0002.jpg",
    "history":{"oid":90000002,"epid":0,"bvid":"BV1HB411b2bB","page":1,"cid":137650102,"part":"","business":"archive","dt":2},
    "videos":1,"author_name":"UP主乙","author_mid":512,"view_at":1760690000,"progress":-1,"duration":600},
    {"title":"某篇专栏","cover":"","covers":["https://i0.hdslb.com/bfs/article/art-0001.jpg"],
    "history":{"oid":6470274,"epid":0,"bvid":"","page":0,"cid":0,"part":"","business":"article","dt":2},
    "author_name":"作者","author_mid":513,"view_at":1760650000,"progress":0,"duration":0},
    {"title":"历史视频三","cover":"https://i0.hdslb.com/bfs/archive/his-0003.jpg",
    "history":{"oid":90000003,"epid":0,"bvid":"BV1HC411c3cC","page":1,"cid":0,"part":"","business":"archive","dt":33},
    "videos":1,"author_name":"UP主丙","author_mid":514,"view_at":1760600000,"progress":0,"duration":90}]}}
    """#

    func testHistoryPagesWithTheCursor() async throws {
        fakeHTTP.routes[historyPath] = (200, firstHistoryPage)
        let first = try await client.history(after: nil)
        XCTAssertEqual(first.items.map(\.bvid), ["BV1HA411a1aA", "BV1HB411b2bB", "BV1HC411c3cC"])
        XCTAssertEqual(first.items[0], HistoryItem(
            bvid: "BV1HA411a1aA", cid: 137650101, title: "历史视频一", cover: "https://i0.hdslb.com/bfs/archive/his-0001.jpg",
            ownerName: "UP主甲", progress: 65, duration: 212, viewAt: 1760700000, device: 1, part: "第二集"))
        XCTAssertEqual(first.items[1].progress, -1)
        XCTAssertNil(first.items[1].part)
        XCTAssertEqual(first.items.map(\.device), [1, 2, 33])
        XCTAssertEqual(Set(first.items.map(\.id)).count, 3)
        XCTAssertEqual(first.next, HistoryCursor(max: 90000003, viewAt: 1760600000))

        let firstQuery = fakeHTTP.query(of: try XCTUnwrap(fakeHTTP.requests(to: historyPath).last))
        XCTAssertEqual(firstQuery["max"], "0")
        XCTAssertEqual(firstQuery["view_at"], "0")
        XCTAssertEqual(firstQuery["business"], "archive")
        XCTAssertEqual(firstQuery["type"], "archive")
        XCTAssertEqual(firstQuery["ps"], "20")
        XCTAssertNil(firstQuery["w_rid"])

        _ = try await client.history(after: first.next)
        let secondQuery = fakeHTTP.query(of: try XCTUnwrap(fakeHTTP.requests(to: historyPath).last))
        XCTAssertEqual(secondQuery["max"], "90000003")
        XCTAssertEqual(secondQuery["view_at"], "1760600000")
        XCTAssertEqual(fakeHTTP.requests(to: historyPath).count, 2)
    }

    func testHistoryEmptyPageEndsPaging() async throws {
        fakeHTTP.routes[historyPath] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":0,"view_at":0,"business":"","ps":20},"tab":[],"list":[]}}"#)
        let empty = try await client.history(after: HistoryCursor(max: 1, viewAt: 2))
        XCTAssertEqual(empty.items, [])
        XCTAssertNil(empty.next)

        fakeHTTP.routes[historyPath] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":5,"view_at":6},"list":null}}"#)
        let nullList = try await client.history(after: nil)
        XCTAssertEqual(nullList.items, [])
        XCTAssertNil(nullList.next)
    }

    func testHistoryZeroCursorWithRowsEndsPagingInsteadOfRestarting() async throws {
        // max=0 and view_at=0 means "from the top" to the server, so passing it back would loop forever.
        let zero = firstHistoryPage.replacingOccurrences(
            of: #""cursor":{"max":90000003,"view_at":1760600000"#, with: #""cursor":{"max":0,"view_at":0"#)
        fakeHTTP.routes[historyPath] = (200, zero)
        let page = try await client.history(after: nil)
        XCTAssertEqual(page.items.count, 3)
        XCTAssertNil(page.next)
    }

    func testHistoryPageOfOnlyUnplayableRowsStillAdvances() async throws {
        let articleOnly = #"""
        {"code":0,"message":"0","ttl":1,"data":{"cursor":{"max":6470274,"view_at":1760650000,"business":"archive","ps":20},"list":[
        {"title":"某篇专栏","cover":"","history":{"oid":6470274,"bvid":"","page":0,"cid":0,"part":"","business":"article","dt":2},"author_name":"作者","view_at":1760650000,"progress":0,"duration":0}]}}
        """#
        fakeHTTP.routes[historyPath] = (200, articleOnly)
        let page = try await client.history(after: nil)
        XCTAssertEqual(page.items, [])
        XCTAssertEqual(page.next, HistoryCursor(max: 6470274, viewAt: 1760650000))
    }

    func testHistoryNeedsALogin() async throws {
        fakeHTTP.routes[historyPath] = (200, #"{"code":-101,"message":"账号未登录","ttl":1}"#)
        do {
            _ = try await client.history(after: nil)
            XCTFail("expected -101")
        } catch let error as BiliError {
            XCTAssertTrue(error.needsLogin)
        }
    }

    func testDeviceKindFollowsTheDtCode() {
        func kind(_ dt: Int) -> HistoryDeviceKind {
            HistoryItem(bvid: "BV1", cid: 0, title: "", cover: "", ownerName: "", progress: 0, duration: 0, viewAt: 0, device: dt, part: nil).deviceKind
        }
        XCTAssertEqual([1, 3, 5, 7].map { kind($0) }, Array(repeating: HistoryDeviceKind.phone, count: 4))
        XCTAssertEqual([2, 33].map { kind($0) }, [HistoryDeviceKind.pc, .pc])
        XCTAssertEqual([0, 4, 6, 9, 100].map { kind($0) }, Array(repeating: HistoryDeviceKind.padOrTV, count: 5))
    }
}
