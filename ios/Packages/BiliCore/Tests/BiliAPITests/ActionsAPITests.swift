import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BiliAPI

final class ActionsAPITests: XCTestCase {
    private let bvid = "BV1GJ411x7h7"
    private let aid: Int64 = 80433022
    private let videoReferer = "https://www.bilibili.com/video/BV1GJ411x7h7"
    private let okEmpty = #"{"code":0,"message":"0","ttl":1,"data":null}"#

    private var http: FakeHTTP!
    private var client: BiliClient!

    override func setUp() {
        http = FakeHTTP()
        client = makeTestClient(http, cookies: ["bili_jct": "TOKEN", "SESSDATA": "s", "buvid3": "b3", "buvid4": "b4"])
    }

    private func sent(_ path: String) throws -> HTTPRequest {
        try XCTUnwrap(http.requests(to: path).first, "no request to \(path)")
    }

    func testRelationSendsAidAndBvidAndDecodes() async throws {
        let path = "/x/web-interface/archive/relation"
        http.routes[path] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"attention":true,"favorite":false,"season_fav":false,"like":true,"dislike":false,"coin":2}}"#)
        let relation = try await client.relation(aid: aid, bvid: bvid)
        XCTAssertEqual(relation, VideoRelation(like: true, dislike: false, favorite: false, attention: true, coins: 2))
        let request = try sent(path)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(http.query(of: request), ["aid": "80433022", "bvid": bvid])
    }

    func testRelationDefaultsMissingFieldsAndAcceptsNumericFlags() async throws {
        let path = "/x/web-interface/archive/relation"
        http.routes[path] = (200, #"{"code":0,"data":{"like":1,"coin":1}}"#)
        let relation = try await client.relation(aid: aid, bvid: bvid)
        XCTAssertEqual(relation, VideoRelation(like: true, dislike: false, favorite: false, attention: false, coins: 1))
    }

    func testUploaderCardDecodesTheNestedCardAndStringMid() async throws {
        let path = "/x/web-interface/card"
        http.routes[path] = (200, #"""
        {"code":0,"message":"0","ttl":1,"data":{"card":{"mid":"4242","name":"UP主","face":"https://i0.hdslb.com/bfs/face/face-0001.jpg","fans":1,"attention":9,"vip":{"type":2,"status":1,"label":{"text":"年度大会员"}}},"following":true,"archive_count":321,"article_count":0,"follower":123456,"like_num":99}}
        """#)
        let card = try await client.uploaderCard(mid: 4242)
        XCTAssertEqual(card, UploaderCard(mid: 4242, name: "UP主", face: "https://i0.hdslb.com/bfs/face/face-0001.jpg",
                                          fans: 123456, videos: 321, isVip: true, following: true))
        let request = try sent(path)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(http.query(of: request), ["mid": "4242", "photo": "false"])
    }

    func testUploaderCardWithoutVipOrFollowingReadsAsFalse() async throws {
        http.routes["/x/web-interface/card"] = (200, #"{"code":0,"data":{"card":{"mid":7,"name":"普通UP","face":"f","vip":{"type":0,"status":0}},"archive_count":0,"follower":0}}"#)
        let card = try await client.uploaderCard(mid: 7)
        XCTAssertEqual(card.mid, 7)
        XCTAssertFalse(card.isVip)
        XCTAssertFalse(card.following)
        XCTAssertEqual(card.videos, 0)
    }

    func testUploaderCardWithoutACardObjectFails() async {
        http.routes["/x/web-interface/card"] = (200, #"{"code":0,"data":{"following":false}}"#)
        do {
            _ = try await client.uploaderCard(mid: 7)
            XCTFail("expected an error")
        } catch {
            guard case .decoding = error as? BiliError else { return XCTFail("\(error)") }
        }
    }

    func testLikeSendsLikeOne() async throws {
        let path = "/x/web-interface/archive/like"
        http.routes[path] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"toast":"点赞成功"}}"#)
        try await client.like(aid: aid, bvid: bvid, on: true)
        let request = try sent(path)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request), "aid=80433022&csrf=TOKEN&like=1")
        XCTAssertEqual(request.headers["Referer"], videoReferer)
    }

    func testUnlikeSendsLikeTwo() async throws {
        let path = "/x/web-interface/archive/like"
        http.routes[path] = (200, okEmpty)
        try await client.like(aid: aid, bvid: bvid, on: false)
        XCTAssertEqual(http.bodyText(of: try sent(path)), "aid=80433022&csrf=TOKEN&like=2")
    }

    func testTripleSendsTheWebFormAndDecodes() async throws {
        let path = "/x/web-interface/archive/like/triple"
        http.routes[path] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"like":true,"coin":true,"fav":true,"multiply":2,"prompt":false}}"#)
        let result = try await client.triple(aid: aid, bvid: bvid)
        XCTAssertEqual(result, TripleResult(like: true, coin: true, favorite: true, multiply: 2))
        let request = try sent(path)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request),
                       "aid=80433022&csrf=TOKEN&eab_x=2&ga=1&ramval=0&source=web_normal&spmid=333.788.0.0"
                       + "&statistics=%7B%22appId%22%3A100%2C%22platform%22%3A5%7D")
        XCTAssertEqual(request.headers["Referer"], videoReferer)
    }

    func testTriplePartlyDoneKeepsEachFlag() async throws {
        http.routes["/x/web-interface/archive/like/triple"] = (200, #"{"code":0,"data":{"like":true,"coin":false,"fav":true,"multiply":0}}"#)
        let result = try await client.triple(aid: aid, bvid: bvid)
        XCTAssertEqual(result, TripleResult(like: true, coin: false, favorite: true, multiply: 0))
    }

    func testCoinSendsMultiplyAndSelectLike() async throws {
        let path = "/x/web-interface/coin/add"
        http.routes[path] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"like":true}}"#)
        try await client.coin(aid: aid, bvid: bvid, multiply: 2, alsoLike: true)
        let request = try sent(path)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request), "aid=80433022&csrf=TOKEN&multiply=2&select_like=1")
        XCTAssertEqual(request.headers["Referer"], videoReferer)
    }

    func testCoinWithoutLikeSendsSelectLikeZero() async throws {
        let path = "/x/web-interface/coin/add"
        http.routes[path] = (200, okEmpty)
        try await client.coin(aid: aid, bvid: bvid, multiply: 1, alsoLike: false)
        XCTAssertEqual(http.bodyText(of: try sent(path)), "aid=80433022&csrf=TOKEN&multiply=1&select_like=0")
    }

    func testCoinErrorKeepsServerMessage() async {
        http.routes["/x/web-interface/coin/add"] = (200, #"{"code":34005,"message":"超过投币上限啦~","ttl":1}"#)
        do {
            try await client.coin(aid: aid, bvid: bvid, multiply: 2, alsoLike: false)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: 34005, message: "超过投币上限啦~"))
        }
    }

    func testCoinBalanceReadsMoneyFromTheAccountHost() async throws {
        let path = "/site/getCoin"
        http.routes[path] = (200, #"{"code":0,"status":true,"data":{"money":123.5}}"#)
        let balance = try await client.coinBalance()
        XCTAssertEqual(balance, 123.5)
        let request = try sent(path)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.host, "account.bilibili.com")
        XCTAssertEqual(request.headers["Cookie"]?.contains("SESSDATA=s"), true)
    }

    func testCoinBalanceAcceptsAWholeNumberAndAMissingMoney() async throws {
        http.routes["/site/getCoin"] = (200, #"{"code":0,"data":{"money":6}}"#)
        let whole = try await client.coinBalance()
        XCTAssertEqual(whole, 6)
        http.routes["/site/getCoin"] = (200, #"{"code":0,"data":{"money":null}}"#)
        let none = try await client.coinBalance()
        XCTAssertEqual(none, 0)
    }

    func testFavouriteFoldersSendsTheQueryAndDecodes() async throws {
        let path = "/x/v3/fav/folder/created/list-all"
        http.routes[path] = (200, #"""
        {"code":0,"message":"0","ttl":1,"data":{"count":2,"list":[
        {"id":1001,"fid":10,"mid":4242,"attr":2,"title":"默认收藏夹","fav_state":1,"media_count":12},
        {"id":1002,"fid":11,"mid":4242,"attr":3,"title":"私密夹","fav_state":0,"media_count":0}],"season":null}}
        """#)
        let folders = try await client.favouriteFolders(mid: 4242, aid: aid)
        XCTAssertEqual(folders, [
            FavFolder(id: 1001, title: "默认收藏夹", count: 12, isPrivate: false, contains: true, isDefault: false),
            FavFolder(id: 1002, title: "私密夹", count: 0, isPrivate: true, contains: false, isDefault: false),
        ])
        let request = try sent(path)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(http.query(of: request), ["up_mid": "4242", "rid": "80433022", "type": "2"])
    }

    func testFavouriteFolderFlags() async throws {
        http.routes["/x/v3/fav/folder/created/list-all"] = (200, #"""
        {"code":0,"data":{"count":4,"list":[
        {"id":1,"attr":0,"title":"a","fav_state":0,"media_count":1},
        {"id":2,"attr":1,"title":"b","fav_state":1,"media_count":2},
        {"id":3,"attr":2,"title":"c","fav_state":0,"media_count":3},
        {"id":4,"attr":3,"title":"d","fav_state":1,"media_count":4}]}}
        """#)
        let folders = try await client.favouriteFolders(mid: 4242, aid: aid)
        XCTAssertEqual(folders.map(\.isPrivate), [false, true, false, true])
        XCTAssertEqual(folders.map(\.isDefault), [true, true, false, false])
        XCTAssertEqual(folders.map(\.contains), [false, true, false, true])
        XCTAssertEqual(folders.map(\.count), [1, 2, 3, 4])
    }

    func testFavouriteFoldersToleratesNoListAndABrokenFolder() async throws {
        http.routes["/x/v3/fav/folder/created/list-all"] = (200, #"{"code":0,"data":{"count":0,"list":null}}"#)
        let none = try await client.favouriteFolders(mid: 1, aid: aid)
        XCTAssertEqual(none, [])
        http.routes["/x/v3/fav/folder/created/list-all"] = (200, #"{"code":0,"data":{"list":[{"title":"没有编号"},{"id":5,"title":"好的"}]}}"#)
        let folders = try await client.favouriteFolders(mid: 1, aid: aid)
        XCTAssertEqual(folders.map(\.id), [5])
        XCTAssertEqual(folders.first?.contains, false)
    }

    func testUpdateFavouritesSendsBothIdListsAndTheVideo() async throws {
        let path = "/x/v3/fav/resource/batch-deal"
        http.routes[path] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"prompt":false}}"#)
        try await client.updateFavourites(aid: aid, add: [1001, 1003], remove: [1002])
        let request = try sent(path)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request),
                       "add_media_ids=1001%2C1003&csrf=TOKEN&del_media_ids=1002&resources=80433022%3A2&rid=80433022&type=2")
    }

    func testUpdateFavouritesWithAnEmptySideSendsAnEmptyField() async throws {
        let path = "/x/v3/fav/resource/batch-deal"
        http.routes[path] = (200, okEmpty)
        try await client.updateFavourites(aid: aid, add: [], remove: [7])
        XCTAssertEqual(http.bodyText(of: try sent(path)),
                       "add_media_ids=&csrf=TOKEN&del_media_ids=7&resources=80433022%3A2&rid=80433022&type=2")
    }

    func testCreateFolderSendsPrivacyAndReturnsTheNewFolder() async throws {
        let path = "/x/v3/fav/folder/add"
        http.routes[path] = (200, #"{"code":0,"message":"0","ttl":1,"data":{"id":2001,"fid":20,"mid":4242,"attr":1,"title":"新夹 & 子","media_count":0,"fav_state":0}}"#)
        let folder = try await client.createFolder(title: "新夹 & 子", isPrivate: true)
        XCTAssertEqual(folder, FavFolder(id: 2001, title: "新夹 & 子", count: 0, isPrivate: true, contains: false, isDefault: true))
        let request = try sent(path)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request), "csrf=TOKEN&privacy=1&title=%E6%96%B0%E5%A4%B9%20%26%20%E5%AD%90")
    }

    func testCreatePublicFolderSendsPrivacyZero() async throws {
        let path = "/x/v3/fav/folder/add"
        http.routes[path] = (200, #"{"code":0,"data":{"id":2002,"attr":0,"title":"x"}}"#)
        _ = try await client.createFolder(title: "x", isPrivate: false)
        XCTAssertEqual(http.bodyText(of: try sent(path)), "csrf=TOKEN&privacy=0&title=x")
    }

    func testCountShareSendsTheAid() async throws {
        let path = "/x/web-interface/share/add"
        http.routes[path] = (200, #"{"code":0,"message":"0","ttl":1,"data":678}"#)
        try await client.countShare(aid: aid)
        let request = try sent(path)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request), "aid=80433022&csrf=TOKEN")
    }

    func testFollowSendsActOneWithTheSpaceReferer() async throws {
        let path = "/x/relation/modify"
        http.routes[path] = (200, okEmpty)
        try await client.follow(mid: 4242, on: true)
        let request = try sent(path)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request), "act=1&csrf=TOKEN&fid=4242&re_src=14")
        XCTAssertEqual(request.headers["Referer"], "https://space.bilibili.com/4242")
    }

    func testUnfollowSendsActTwo() async throws {
        let path = "/x/relation/modify"
        http.routes[path] = (200, okEmpty)
        try await client.follow(mid: 4242, on: false)
        XCTAssertEqual(http.bodyText(of: try sent(path)), "act=2&csrf=TOKEN&fid=4242&re_src=14")
    }

    func testTagsDecodeKindsAndSendBvidAndCid() async throws {
        let path = "/x/web-interface/view/detail/tag"
        http.routes[path] = (200, #"""
        {"code":0,"message":"0","ttl":1,"data":[
        {"tag_id":111,"tag_name":"测试标签","music_id":"","tag_type":"old_channel","jump_url":""},
        {"tag_id":222,"tag_name":"测试话题","music_id":"","tag_type":"topic","jump_url":""},
        {"tag_id":333,"tag_name":"发现《测试曲》","music_id":"MA1","tag_type":"bgm","jump_url":""},
        {"tag_id":444,"tag_name":"没有类型"}]}
        """#)
        let tags = try await client.tags(bvid: bvid, cid: 137649199)
        XCTAssertEqual(tags, [
            VideoTag(id: 111, name: "测试标签", kind: .normal),
            VideoTag(id: 222, name: "测试话题", kind: .topic),
            VideoTag(id: 333, name: "发现《测试曲》", kind: .bgm),
            VideoTag(id: 444, name: "没有类型", kind: .normal),
        ])
        let request = try sent(path)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(http.query(of: request), ["bvid": bvid, "cid": "137649199"])
    }

    func testTagsWithNullDataIsEmpty() async throws {
        http.routes["/x/web-interface/view/detail/tag"] = (200, okEmpty)
        let tags = try await client.tags(bvid: bvid, cid: 1)
        XCTAssertEqual(tags, [])
    }

    func testWritesWithoutACSRFCookieAskForLoginWithoutSending() async {
        let anonymous = makeTestClient(http, cookies: ["buvid3": "b3", "buvid4": "b4"])
        do {
            try await anonymous.like(aid: aid, bvid: bvid, on: true)
            XCTFail("expected -101")
        } catch {
            XCTAssertEqual((error as? BiliError)?.needsLogin, true)
        }
        XCTAssertTrue(http.requests.current.isEmpty)
    }
}
