import XCTest
import BiliShared
import DevLog
@testable import BiliAPI

/// Shaped after a live /x/v2/reply/main response (2026-10-17); every name, id and text here is invented.
private enum CommentFixtures {
    static let memberA = #"""
    {"mid":"1001","uname":"测试用户甲","sex":"保密","sign":"","avatar":"https://i0.hdslb.com/bfs/face/face-a.jpg","rank":"10000",
    "level_info":{"current_level":6,"current_min":0,"current_exp":0,"next_exp":0},
    "pendant":{"pid":4318,"name":"挂件","image":"https://i0.hdslb.com/bfs/garb/item/pendant-a.png","expire":0},
    "vip":{"vipType":2,"vipStatus":1,"label":{"path":"","text":""}},
    "user_sailing":{"pendant":null,"cardbg":{"id":32261,"name":"装扮","image":"https://i0.hdslb.com/bfs/garb/item/card-a.png","fan":{"is_fan":1,"number":95,"color":"#f35543","name":"装扮","num_desc":"000095","num_prefix":"NO."}},"cardbg_with_focus":null}}
    """#

    static let memberB = #"""
    {"mid":"1002","uname":"测试用户乙","avatar":"https://i0.hdslb.com/bfs/face/face-b.jpg",
    "level_info":{"current_level":3},"pendant":{"pid":0,"name":"","image":""},"vip":{"vipType":1,"vipStatus":0},"user_sailing":null}
    """#

    static func reply(rpid: Int64, member: String, message: String, extra: String = "", content: String = "", replies: String = "null") -> String {
        """
        {"rpid":\(rpid),"oid":80433022,"type":1,"mid":1001,"root":0,"parent":0,"count":12,"rcount":10,"state":0,"ctime":1760000000,
        "like":321,"action":1,"member":\(member),
        "content":{"message":"\(message)","members":[]\(content.isEmpty ? "" : "," + content)},
        "replies":\(replies),"up_action":{"like":false,"reply":false},"reply_control":{"time_desc":"3天前发布"\(extra)}}
        """
    }

    /// The root comment with an emote, a mention, a jump link, a picture, an up-liked flag and a location.
    static let rich = #"""
    {"rpid":9001,"oid":80433022,"type":1,"mid":1001,"root":0,"parent":0,"count":12,"rcount":10,"state":0,"ctime":1760000000,
    "like":321,"action":1,"member":
    """# + memberA + #"""
    ,"content":{"message":"看[doge]\n@测试用户乙 在03:15 BV1GJ411x7h7 蓝链",
    "emote":{"[doge]":{"id":1,"url":"https://i0.hdslb.com/bfs/emote/doge.png","meta":{"size":1}}},
    "at_name_to_mid":{"测试用户乙":1002},
    "jump_url":{"蓝链":{"title":"链接标题","state":0,"pc_url":"//search.bilibili.com/all?keyword=x","app_url_schema":"bilibili://search"}},
    "pictures":[{"img_src":"https://i0.hdslb.com/bfs/new_dyn/pic-1.jpg","img_width":1080,"img_height":1920.5,"img_size":12.3}],
    "members":[],"max_line":6},
    "replies":[
    """# + subReply + #"""
    ],"up_action":{"like":true,"reply":false},
    "reply_control":{"time_desc":"3天前发布","location":"IP属地：广东"}}
    """#

    /// A reply to a user who has since renamed: the text keeps the old name, at_name_to_mid holds the new one.
    static let subReply = #"""
    {"rpid":9002,"oid":80433022,"type":1,"mid":1002,"root":9001,"parent":9001,"count":0,"rcount":0,"ctime":1760000500,"like":7,"action":0,
    "member":
    """# + memberB + #"""
    ,"content":{"message":"回复 @旧名字 :同意[笑哭]","at_name_to_mid":{"新名字":1001},
    "emote":{"[笑哭]":{"url":"https://i0.hdslb.com/bfs/emote/cry.png","meta":{"size":2}}},"members":[]},
    "replies":null,"parent_reply_member":{"name":"旧名字"},"up_action":{"like":false,"reply":false},"reply_control":{"time_desc":"2天前发布"}}
    """#

    static let plain = reply(rpid: 9003, member: memberB, message: "普通评论")
    static let pinned = reply(rpid: 9100, member: memberA, message: "置顶评论", extra: #","location":"IP属地：北京""#)

    static func page(replies: [String], top: [String] = [], cursor: String) -> String {
        #"{"code":0,"message":"OK","ttl":1,"data":{"cursor":"# + cursor + #","replies":["# + replies.joined(separator: ",")
            + #"],"top_replies":["# + top.joined(separator: ",") + #"]}}"#
    }

    static let cursorMore = #"{"is_begin":true,"prev":0,"next":2,"is_end":false,"pagination_reply":{"next_offset":"CAEiAggC"},"mode":3,"all_count":1234}"#
    static let cursorEnd = #"{"is_begin":false,"prev":2,"next":0,"is_end":true,"mode":3,"all_count":42}"#

    static let firstPage = page(replies: [rich, plain], top: [pinned], cursor: cursorMore)
    static let lastPage = page(replies: [plain], top: [pinned], cursor: cursorEnd)

    static let thread = #"{"code":0,"message":"OK","ttl":1,"data":{"page":{"num":2,"size":20,"count":45,"acount":45},"root":"# + plain
        + #","replies":["# + rich + "," + subReply + #"]}}"#

    static let emotePanel = #"""
    {"code":0,"message":"OK","ttl":1,"data":{"packages":[
    {"id":1,"text":"小黄脸","url":"https://i0.hdslb.com/bfs/emote/pkg-1.png","type":3,"attr":0,"emote":[
    {"id":10,"package_id":1,"text":"[doge]","url":"https://i0.hdslb.com/bfs/emote/doge.png","type":1,"meta":{"size":1}},
    {"id":11,"package_id":1,"text":"[大笑]","url":"https://i0.hdslb.com/bfs/emote/lol.png","type":1,"meta":{"size":2}}]},
    {"id":2,"text":"颜文字","url":"https://i0.hdslb.com/bfs/emote/pkg-2.png","type":4,"emote":[
    {"id":20,"package_id":2,"text":"(⌒▽⌒)","url":"","type":4,"meta":{"size":1}},
    {"id":21,"package_id":2,"text":"orz"}]},
    {"id":3,"url":"https://i0.hdslb.com/bfs/emote/pkg-3.png","type":1,"emote":null}]}}
    """#
}

final class CommentsAPITests: XCTestCase {
    private let navPath = "/x/web-interface/nav"
    private let signedPath = "/x/v2/reply/wbi/main"
    private let unsignedPath = "/x/v2/reply/main"
    private let threadPath = "/x/v2/reply/reply"
    private let addPath = "/x/v2/reply/add"
    private let spiPath = "/x/frontend/finger/spi"

    private var http: FakeHTTP!
    private var client: BiliClient!

    override func setUp() {
        http = FakeHTTP()
        http.routes[navPath] = (200, Fixtures.navLoggedIn)
        client = makeTestClient(http, cookies: ["bili_jct": "T", "SESSDATA": "s", "buvid3": "b3", "buvid4": "b4"])
    }

    func testCommentPageDecodesMembersPicturesPinnedAndCursor() async throws {
        http.routes[signedPath] = (200, CommentFixtures.firstPage)
        let page = try await client.comments(aid: 80433022, sort: .hot, offset: nil)
        XCTAssertEqual(page.total, 1234)
        XCTAssertEqual(page.nextOffset, "CAEiAggC")
        XCTAssertFalse(page.isEnd)
        XCTAssertEqual(page.comments.map(\.rpid), [9001, 9003])

        let root = page.comments[0]
        XCTAssertEqual(root.id, 9001)
        XCTAssertEqual([root.oid, root.mid, root.root, root.parent, root.ctime, root.likes], [80433022, 1001, 0, 0, 1760000000, 321])
        XCTAssertEqual(root.replyCount, 10)
        XCTAssertEqual(root.action, 1)
        XCTAssertTrue(root.upLiked)
        XCTAssertFalse(root.isPinned)
        XCTAssertEqual(root.location, "广东")
        XCTAssertEqual(root.member, CommentMember(
            mid: 1001, name: "测试用户甲", face: "https://i0.hdslb.com/bfs/face/face-a.jpg", level: 6, isVip: true,
            pendant: "https://i0.hdslb.com/bfs/garb/item/pendant-a.png",
            fanCardImage: "https://i0.hdslb.com/bfs/garb/item/card-a.png", fanCardNumber: "000095", fanCardColor: "#f35543"))
        XCTAssertEqual(root.pictures, [CommentPicture(url: "https://i0.hdslb.com/bfs/new_dyn/pic-1.jpg", width: 1080, height: 1920.5)])
        XCTAssertEqual(root.runs, [
            .text("看"), .emote(token: "[doge]", url: "https://i0.hdslb.com/bfs/emote/doge.png", size: 1), .text("\n"),
            .mention(name: "测试用户乙", mid: 1002), .text(" 在"), .timestamp(label: "03:15", seconds: 195), .text(" "),
            .video(id: "BV1GJ411x7h7"), .text(" "),
            .link(title: "链接标题", url: "https://search.bilibili.com/all?keyword=x"),
        ])

        let plain = page.comments[1]
        XCTAssertEqual(plain.member.pendant, nil)
        XCTAssertEqual(plain.member.fanCardImage, nil)
        XCTAssertEqual(plain.member.fanCardNumber, nil)
        XCTAssertEqual(plain.member.fanCardColor, nil)
        XCTAssertFalse(plain.member.isVip)
        XCTAssertEqual(plain.member.level, 3)
        XCTAssertNil(plain.location)
        XCTAssertEqual(plain.pictures, [])
        XCTAssertEqual(plain.previewReplies, [])
        XCTAssertEqual(plain.runs, [.text("普通评论")])

        let pinned = try XCTUnwrap(page.pinned)
        XCTAssertEqual(pinned.rpid, 9100)
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(pinned.location, "北京")
    }

    func testPreviewRepliesAndARenamedReplyTarget() async throws {
        http.routes[signedPath] = (200, CommentFixtures.firstPage)
        let page = try await client.comments(aid: 80433022, sort: .hot)
        let preview = try XCTUnwrap(page.comments[0].previewReplies.first)
        XCTAssertEqual(preview.rpid, 9002)
        XCTAssertEqual(preview.root, 9001)
        XCTAssertEqual(preview.parent, 9001)
        XCTAssertEqual(preview.action, 0)
        XCTAssertEqual(preview.member.mid, 1002)
        XCTAssertEqual(preview.runs, [
            .text("回复 "), .mention(name: "旧名字", mid: 1001), .text(" :同意"),
            .emote(token: "[笑哭]", url: "https://i0.hdslb.com/bfs/emote/cry.png", size: 2),
        ])
    }

    func testCommentsRequestIsSignedAndCarriesTheCursor() async throws {
        http.routes[signedPath] = (200, CommentFixtures.lastPage)
        _ = try await client.comments(aid: 80433022, sort: .time, offset: nil)
        _ = try await client.comments(aid: 80433022, sort: .hot, offset: "CAEiAggC")
        let sent = http.requests(to: signedPath)
        XCTAssertEqual(sent.count, 2)
        let first = http.query(of: sent[0])
        XCTAssertEqual(first["oid"], "80433022")
        XCTAssertEqual(first["type"], "1")
        XCTAssertEqual(first["mode"], "2")
        XCTAssertEqual(first["pagination_str"], #"{"offset":""}"#)
        XCTAssertNil(first["seek_rpid"])
        XCTAssertEqual(first["w_rid"]?.count, 32)
        XCTAssertNotNil(first["wts"])
        let second = http.query(of: sent[1])
        XCTAssertEqual(second["mode"], "3")
        XCTAssertEqual(second["pagination_str"], #"{"offset":"CAEiAggC"}"#)
        XCTAssertEqual(sent[0].headers["Referer"], BiliClient.referer)
    }

    func testPinnedCommentIsOnlyKeptOnPageOneAndTheEndHasNoOffset() async throws {
        http.routes[signedPath] = (200, CommentFixtures.lastPage)
        let one = try await client.comments(aid: 1, sort: .hot, offset: "")
        XCTAssertNotNil(one.pinned)
        XCTAssertTrue(one.isEnd)
        XCTAssertNil(one.nextOffset)
        XCTAssertEqual(one.total, 42)
        let later = try await client.comments(aid: 1, sort: .hot, offset: "CAEiAggC")
        XCTAssertNil(later.pinned)
        XCTAssertEqual(later.comments.map(\.rpid), [9003])
    }

    func testAMissingNextOffsetEndsTheList() async throws {
        let cursor = #"{"is_end":false,"all_count":3}"#
        http.routes[signedPath] = (200, CommentFixtures.page(replies: [CommentFixtures.plain], cursor: cursor))
        let page = try await client.comments(aid: 1, sort: .hot)
        XCTAssertTrue(page.isEnd)
        XCTAssertNil(page.nextOffset)
    }

    func testOneBrokenCommentDoesNotFailThePage() async throws {
        let broken = #"{"rpid":0,"content":{"message":"没有编号"}}"#
        http.routes[signedPath] = (200, CommentFixtures.page(replies: [broken, CommentFixtures.plain], cursor: CommentFixtures.cursorEnd))
        let page = try await client.comments(aid: 1, sort: .hot)
        XCTAssertEqual(page.comments.map(\.rpid), [9003])
    }

    func testCommentsFallBackToTheUnsignedRouteOnRiskControl() async throws {
        http.routes[signedPath] = (200, #"{"code":-352,"message":"风控校验失败"}"#)
        http.routes[unsignedPath] = (200, CommentFixtures.firstPage)
        let page = try await client.comments(aid: 80433022, sort: .hot, offset: "CAEiAggC")
        XCTAssertEqual(page.comments.count, 2)
        XCTAssertEqual(http.requests(to: signedPath).count, 1)
        let retry = try XCTUnwrap(http.requests(to: unsignedPath).first)
        XCTAssertEqual(http.requests(to: unsignedPath).count, 1)
        let query = http.query(of: retry)
        XCTAssertNil(query["w_rid"])
        XCTAssertNil(query["wts"])
        XCTAssertEqual(query["oid"], "80433022")
        XCTAssertEqual(query["mode"], "3")
        XCTAssertEqual(query["pagination_str"], #"{"offset":"CAEiAggC"}"#)
    }

    func testCommentsFallBackOnCode403AndHTTP412ButOnlyOnce() async throws {
        http.routes[signedPath] = (200, #"{"code":-403,"message":"访问权限不足"}"#)
        http.routes[unsignedPath] = (200, CommentFixtures.lastPage)
        _ = try await client.comments(aid: 1, sort: .hot)
        XCTAssertEqual(http.requests(to: unsignedPath).count, 1)

        http.requests.withLock { $0.removeAll() }
        http.routes[signedPath] = (412, "")
        http.routes[spiPath] = (200, Fixtures.spi)
        _ = try await client.comments(aid: 1, sort: .hot)
        XCTAssertEqual(http.requests(to: unsignedPath).count, 1)

        http.requests.withLock { $0.removeAll() }
        http.routes[signedPath] = (200, #"{"code":-352,"message":"风控校验失败"}"#)
        http.routes[unsignedPath] = (200, #"{"code":-352,"message":"风控校验失败"}"#)
        do {
            _ = try await client.comments(aid: 1, sort: .hot)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: -352, message: "风控校验失败"))
        }
        XCTAssertEqual(http.requests(to: unsignedPath).count, 1)
    }

    func testClosedCommentsThrowTheServerMessage() async {
        for (code, message) in [(12002, "评论区已关闭"), (12061, "UP主已关闭评论区")] {
            http.requests.withLock { $0.removeAll() }
            http.routes[signedPath] = (200, #"{"code":\#(code),"message":"\#(message)"}"#)
            do {
                _ = try await client.comments(aid: 1, sort: .hot)
                XCTFail("expected an error")
            } catch {
                XCTAssertEqual(error as? BiliError, .api(code: code, message: message))
            }
            XCTAssertTrue(http.requests(to: unsignedPath).isEmpty)
        }
    }

    func testPostCommentReplyFields() async throws {
        let posted = #"{"code":0,"message":"0","data":{"success_action":0,"reply":"# + CommentFixtures.plain + "}}"
        http.routes["POST " + addPath] = (200, posted)

        let reply = try await client.postComment(aid: 80433022, message: "回复 & 内容", root: 10, parent: 11)
        XCTAssertEqual(reply.rpid, 9003)
        var request = try XCTUnwrap(http.requests(to: addPath).last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(http.bodyText(of: request), "csrf=T&message=%E5%9B%9E%E5%A4%8D%20%26%20%E5%86%85%E5%AE%B9&oid=80433022&parent=11&root=10&type=1")
        XCTAssertEqual(request.headers["Referer"], "https://www.bilibili.com/video/av80433022")

        _ = try await client.postComment(aid: 80433022, message: "顶层")
        request = try XCTUnwrap(http.requests(to: addPath).last)
        let body = http.bodyText(of: request)
        XCTAssertFalse(body.contains("root="))
        XCTAssertFalse(body.contains("parent="))
        XCTAssertFalse(body.contains("sync_to_dynamic"))

        _ = try await client.postComment(aid: 80433022, message: "顶层", syncToDynamic: true)
        request = try XCTUnwrap(http.requests(to: addPath).last)
        XCTAssertTrue(http.bodyText(of: request).contains("sync_to_dynamic=1"))
    }

    func testPostCommentWithoutLoginThrowsWithoutSending() async {
        let loggedOut = makeTestClient(http)
        do {
            _ = try await loggedOut.postComment(aid: 1, message: "x")
            XCTFail("expected -101")
        } catch {
            XCTAssertEqual((error as? BiliError)?.needsLogin, true)
        }
        XCTAssertTrue(http.requests(to: addPath).isEmpty)
    }

    func testThreadQuery() async throws {
        http.routes[threadPath] = (200, CommentFixtures.thread)
        let page = try await client.thread(aid: 80433022, root: 9003, page: 2, sort: .time)
        let query = http.query(of: try XCTUnwrap(http.requests(to: threadPath).first))
        XCTAssertEqual(query["oid"], "80433022")
        XCTAssertEqual(query["type"], "1")
        XCTAssertEqual(query["root"], "9003")
        XCTAssertEqual(query["pn"], "2")
        XCTAssertEqual(query["ps"], "20")
        XCTAssertEqual(query["sort"], "0")
        XCTAssertNil(query["w_rid"])
        XCTAssertEqual(page.root.rpid, 9003)
        XCTAssertEqual(page.replies.map(\.rpid), [9001, 9002])
        XCTAssertEqual(page.total, 45)
        XCTAssertFalse(page.isEnd)

        _ = try await client.thread(aid: 80433022, root: 9003, page: 1, sort: .hot)
        XCTAssertEqual(http.query(of: try XCTUnwrap(http.requests(to: threadPath).last))["sort"], "1")
    }

    func testThreadEndsOnTheLastPageOrAnEmptyOne() async throws {
        let root = CommentFixtures.plain
        http.routes[threadPath] = (200, #"{"code":0,"data":{"page":{"num":3,"size":20,"count":45},"root":"# + root + #","replies":[]}}"#)
        let empty = try await client.thread(aid: 1, root: 9003, page: 3, sort: .time)
        XCTAssertTrue(empty.isEnd)
        http.routes[threadPath] = (200, #"{"code":0,"data":{"page":{"num":3,"size":20,"count":45},"root":"# + root + #","replies":["# + root + "]}}")
        let last = try await client.thread(aid: 1, root: 9003, page: 3, sort: .time)
        XCTAssertTrue(last.isEnd)
        XCTAssertEqual(last.replies.count, 1)
    }

    func testLikeHateAndDeleteForms() async throws {
        let ok = #"{"code":0,"message":"0","data":null}"#
        http.routes["POST /x/v2/reply/action"] = (200, ok)
        http.routes["POST /x/v2/reply/hate"] = (200, ok)
        http.routes["POST /x/v2/reply/del"] = (200, ok)

        try await client.likeComment(aid: 80433022, rpid: 9001, on: true)
        try await client.likeComment(aid: 80433022, rpid: 9001, on: false)
        try await client.hateComment(aid: 80433022, rpid: 9001, on: true)
        try await client.hateComment(aid: 80433022, rpid: 9001, on: false)
        try await client.deleteComment(aid: 80433022, rpid: 9001)

        let likes = http.requests(to: "/x/v2/reply/action").map { http.bodyText(of: $0) }
        XCTAssertEqual(likes, ["action=1&csrf=T&oid=80433022&rpid=9001&type=1", "action=0&csrf=T&oid=80433022&rpid=9001&type=1"])
        let hates = http.requests(to: "/x/v2/reply/hate").map { http.bodyText(of: $0) }
        XCTAssertEqual(hates, ["action=1&csrf=T&oid=80433022&rpid=9001&type=1", "action=0&csrf=T&oid=80433022&rpid=9001&type=1"])
        let deletes = http.requests(to: "/x/v2/reply/del").map { http.bodyText(of: $0) }
        XCTAssertEqual(deletes, ["csrf=T&oid=80433022&rpid=9001&type=1"])
    }

    func testEmotePackagesFlagTextPackages() async throws {
        http.routes["/x/emote/user/panel/web"] = (200, CommentFixtures.emotePanel)
        let packages = try await client.emotePackages()
        let request = try XCTUnwrap(http.requests(to: "/x/emote/user/panel/web").first)
        XCTAssertEqual(http.query(of: request), ["business": "reply"])
        XCTAssertEqual(packages.map(\.id), [1, 2, 3])
        XCTAssertEqual(packages.map(\.isText), [false, true, false])
        XCTAssertEqual(packages[0].name, "小黄脸")
        XCTAssertEqual(packages[0].icon, "https://i0.hdslb.com/bfs/emote/pkg-1.png")
        XCTAssertEqual(packages[0].emotes, [
            Emote(token: "[doge]", url: "https://i0.hdslb.com/bfs/emote/doge.png", large: false),
            Emote(token: "[大笑]", url: "https://i0.hdslb.com/bfs/emote/lol.png", large: true),
        ])
        XCTAssertEqual(packages[1].emotes, [Emote(token: "(⌒▽⌒)", url: "", large: false), Emote(token: "orz", url: "", large: false)])
        XCTAssertEqual(packages[2].emotes, [])
        XCTAssertEqual(packages[2].name, "")
    }
}
