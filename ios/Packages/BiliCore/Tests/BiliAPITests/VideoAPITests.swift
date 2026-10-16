import XCTest
import BiliShared
import DevLog
@testable import BiliAPI

final class VideoAPITests: XCTestCase {
    private let navPath = "/x/web-interface/nav"
    private let viewPath = "/x/web-interface/wbi/view"
    private let playerPath = "/x/player/wbi/v2"
    private let relatedPath = "/x/web-interface/archive/related"
    private let onlinePath = "/x/player/online/total"
    private let heartbeatPath = "/x/click-interface/web/heartbeat"
    private let watchLaterPath = "/x/v2/history/toview/add"

    private var fakeHTTP: FakeHTTP!
    private var client: BiliClient!

    override func setUp() {
        fakeHTTP = FakeHTTP()
        fakeHTTP.routes[navPath] = (200, Fixtures.navLoggedIn)
        client = BiliClient(transport: fakeHTTP, cookies: CookieJar(["bili_jct": "T", "SESSDATA": "s", "buvid3": "b3", "buvid4": "b4"]),
                            now: { Date(timeIntervalSince1970: 1_702_204_169) }, logger: Logger(session: "test"))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try XCTUnwrap(JSONDecoder().decode(BiliEnvelope<T>.self, from: Data(json.utf8)).data)
    }

    func testVideoDetailDecodesSeasonStaffStatsAndShape() async throws {
        fakeHTTP.routes[viewPath] = (200, Fixtures.viewDetail)
        let detail = try await client.videoDetail(bvid: "BV1GJ411x7h7")
        XCTAssertEqual(detail.season?.sections.map(\.episodes.count), [2, 1])
        XCTAssertEqual(detail.season?.sections[0].episodes[1].cid, 137649300)
        XCTAssertEqual(detail.stat.like, 9131)
        XCTAssertTrue(detail.isVertical)
        XCTAssertEqual(detail.honor, "活动")
        XCTAssertEqual(detail.descParts.last?.mentionMid, 42)
        XCTAssertNotNil(fakeHTTP.query(of: fakeHTTP.requests(to: viewPath)[0])["w_rid"])
        XCTAssertEqual(fakeHTTP.query(of: fakeHTTP.requests(to: viewPath)[0])["bvid"], "BV1GJ411x7h7")
    }

    func testVideoDetailFieldsAndSeasonEpisodeFromArc() throws {
        let detail = try decode(VideoDetail.self, Fixtures.viewDetail)
        XCTAssertEqual(detail.bvid, "BV1GJ411x7h7")
        XCTAssertEqual(detail.aid, 80433022)
        XCTAssertEqual(detail.title, "测试视频")
        XCTAssertEqual(detail.cover, "https://i0.hdslb.com/bfs/archive/cover-0001.jpg")
        XCTAssertEqual(detail.pubdate, 1760000000)
        XCTAssertEqual(detail.duration, 312)
        XCTAssertEqual(detail.copyright, 1)
        XCTAssertEqual(detail.owner, VideoOwner(mid: 1, name: "UP主", face: "https://i0.hdslb.com/bfs/face/face-0001.jpg"))
        XCTAssertEqual(detail.stat.view, 123456)
        XCTAssertEqual(detail.stat.favorite, 7890)
        XCTAssertEqual(detail.pages.map(\.cid), [137649199, 137649200])
        XCTAssertEqual(detail.staff, [])
        XCTAssertNil(detail.redirectURL)
        XCTAssertEqual(detail.descParts, [DescPart(text: "视频简介 "), DescPart(text: "测试用户", mentionMid: 42)])
        let season = try XCTUnwrap(detail.season)
        XCTAssertEqual(season.title, "测试合集")
        XCTAssertEqual(season.sections.map(\.title), ["正片", "特别篇"])
        XCTAssertEqual(season.sections[0].episodes[1], SeasonEpisode(
            aid: 80433100, bvid: "BV1AB411c7mD", cid: 137649300, title: "第二集",
            cover: "https://i0.hdslb.com/bfs/archive/ep-0002.jpg", duration: 300, pubdate: 1760000500, views: 2000, danmaku: 20))
    }

    func testRotatedFileSwapsTheDisplayedShape() throws {
        let rotated = Fixtures.viewDetail.replacingOccurrences(of: #""rotate":0"#, with: #""rotate":1"#)
        let detail = try decode(VideoDetail.self, rotated)
        XCTAssertFalse(detail.isVertical)
        XCTAssertEqual(detail.width, 1920)
        XCTAssertEqual(detail.height, 1080)
    }

    func testHiddenCountsAndBrokenElementsDoNotFailTheDetail() throws {
        let hidden = Fixtures.viewDetail
            .replacingOccurrences(of: #""view":123456"#, with: #""view":"--""#)
            .replacingOccurrences(of: #""cid":137649400,"title":"番外","bvid":"BV1CD411d8nE""#, with: #""cid":137649400,"title":"番外""#)
        let detail = try decode(VideoDetail.self, hidden)
        XCTAssertEqual(detail.stat.view, 0)
        XCTAssertEqual(detail.stat.like, 9131)
        // The special section's only episode has no bvid in either place, so it is dropped but the section stays.
        XCTAssertEqual(detail.season?.sections.map(\.episodes.count), [2, 0])
    }

    func testWrongTypeInDecorativeBlocksDoesNotFailTheDetail() throws {
        let broken = Fixtures.viewDetail
            .replacingOccurrences(of: #""staff":[]"#, with: #""staff":"none""#)
            .replacingOccurrences(of: #""desc_v2":[{"raw_text":"视频简介 ","type":1,"biz_id":0},{"raw_text":"测试用户","type":2,"biz_id":42}]"#, with: #""desc_v2":"oops""#)
            .replacingOccurrences(of: #""honor_reply":{"honor":[{"aid":80433022,"type":4,"desc":"活动","weekly_recommend_num":0}]}"#, with: #""honor_reply":{"honor":"none"}"#)
        XCTAssertTrue(broken.contains(#""staff":"none""#) && broken.contains(#""desc_v2":"oops""#) && broken.contains(#""honor":"none""#))
        let detail = try decode(VideoDetail.self, broken)
        XCTAssertEqual(detail.staff, [])
        XCTAssertEqual(detail.descParts, [DescPart(text: "视频简介 @测试用户")])
        XCTAssertNil(detail.honor)
        XCTAssertEqual(detail.title, "测试视频")
        XCTAssertEqual(detail.pages.count, 2)
    }

    func testDescriptionWithoutPartsFallsBackToThePlainText() throws {
        let plain = Fixtures.viewDetail.replacingOccurrences(of: #""desc_v2":[{"raw_text":"视频简介 ","type":1,"biz_id":0},{"raw_text":"测试用户","type":2,"biz_id":42}],"#, with: #""desc_v2":null,"#)
        let detail = try decode(VideoDetail.self, plain)
        XCTAssertEqual(detail.descParts, [DescPart(text: "视频简介 @测试用户")])
    }

    func testPlayerInfoKeepsChaptersOnlyForType2() async throws {
        fakeHTTP.routes[playerPath] = (200, Fixtures.playerV2)
        let info = try await client.playerInfo(bvid: "BV1GJ411x7h7", cid: 137649199)
        XCTAssertEqual(info.lastPlayCid, 137649200)
        XCTAssertEqual(info.chapters, [Chapter(from: 0, to: 60, title: "开场"), Chapter(from: 60, to: 150, title: "正片"),
                                       Chapter(from: 150, to: 212, title: "结尾")])
        let query = fakeHTTP.query(of: fakeHTTP.requests(to: playerPath)[0])
        XCTAssertEqual(query["cid"], "137649199")
        XCTAssertNotNil(query["w_rid"])

        fakeHTTP.routes[playerPath] = (200, Fixtures.playerV2Highlights)
        let highlights = try await client.playerInfo(bvid: "BV1GJ411x7h7", cid: 137649199)
        XCTAssertEqual(highlights.chapters, [])
    }

    func testRelatedDropsRedirectedItems() async throws {
        fakeHTTP.routes[relatedPath] = (200, Fixtures.related)
        let cards = try await client.related(bvid: "BV1GJ411x7h7")
        XCTAssertEqual(cards, [VideoCard(aid: 90000001, bvid: "BV1EF411e9oF", cid: 137650001, title: "相关视频一",
                                         cover: "https://i0.hdslb.com/bfs/archive/rel-0001.jpg", duration: 605, ownerMid: 77,
                                         ownerName: "另一个UP", views: 50000, danmaku: 120, likes: 1500)])
        XCTAssertEqual(fakeHTTP.query(of: fakeHTTP.requests(to: relatedPath)[0])["bvid"], "BV1GJ411x7h7")
    }

    func testRelatedDropsItemsWithoutABvid() async throws {
        fakeHTTP.routes[relatedPath] = (200, Fixtures.related.replacingOccurrences(of: #""bvid":"BV1EF411e9oF""#, with: #""bvid":"""#))
        let cards = try await client.related(bvid: "BV1GJ411x7h7")
        XCTAssertEqual(cards, [])
    }

    func testRelatedWithNullDataIsEmpty() async throws {
        fakeHTTP.routes[relatedPath] = (200, #"{"code":0,"message":"0","data":null}"#)
        let cards = try await client.related(bvid: "BV1GJ411x7h7")
        XCTAssertEqual(cards, [])
    }

    func testRelatedStillThrowsOnAnApiError() async throws {
        fakeHTTP.routes[relatedPath] = (200, #"{"code":-404,"message":"啥都木有","data":null}"#)
        do {
            _ = try await client.related(bvid: "BV1GJ411x7h7")
            XCTFail("expected an api error")
        } catch {
            guard case .api(let code, _) = error as? BiliError else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(code, -404)
        }
    }

    func testOnlineCountIsTheDisplayString() async throws {
        fakeHTTP.routes[onlinePath] = (200, Fixtures.online)
        let total = try await client.onlineCount(aid: 80433022, bvid: "BV1GJ411x7h7", cid: 137649199)
        XCTAssertEqual(total, "1.2万+")
        let query = fakeHTTP.query(of: fakeHTTP.requests(to: onlinePath)[0])
        XCTAssertEqual(query["aid"], "80433022")
        XCTAssertEqual(query["cid"], "137649199")
        XCTAssertEqual(query["bvid"], "BV1GJ411x7h7")
    }

    func testHeartbeatFormFields() async throws {
        fakeHTTP.routes[heartbeatPath] = (200, #"{"code":0,"message":"0","ttl":1}"#)
        try await client.heartbeat(bvid: "BV1", cid: 2, playedTime: -1)
        let request = try XCTUnwrap(fakeHTTP.requests(to: heartbeatPath).first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(String(decoding: request.body ?? Data(), as: UTF8.self), "bvid=BV1&cid=2&csrf=T&played_time=-1&type=3")
    }

    func testAddToWatchLaterForm() async throws {
        fakeHTTP.routes[watchLaterPath] = (200, #"{"code":0,"message":"0","ttl":1,"data":null}"#)
        try await client.addToWatchLater(aid: 80433022)
        let request = try XCTUnwrap(fakeHTTP.requests(to: watchLaterPath).first)
        XCTAssertEqual(String(decoding: request.body ?? Data(), as: UTF8.self), "aid=80433022&csrf=T")
    }

    func testPlayURLCarriesResumeFields() throws {
        let resumed = try decode(PlayURLInfo.self, Fixtures.playURLResume)
        XCTAssertEqual(resumed.lastPlayTimeMs, 65000)
        XCTAssertEqual(resumed.lastPlayCid, 137649199)
        let old = try decode(PlayURLInfo.self, Fixtures.playURL)
        XCTAssertEqual(old.lastPlayTimeMs, 0)
        XCTAssertEqual(old.lastPlayCid, 0)
    }
}
