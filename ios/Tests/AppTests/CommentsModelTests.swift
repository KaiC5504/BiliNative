import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class CommentsModelTests: XCTestCase {
    private let listPath = "/x/v2/reply/wbi/main"
    private let threadPath = "/x/v2/reply/reply"
    private let likePath = "/x/v2/reply/action"
    private let deletePath = "/x/v2/reply/del"

    func testPagingPassesTheOffsetAndStopsAtTheEnd() async throws {
        let http = CommentsHTTP()
        http.list = { query in
            query["pagination_str"]?.contains("PAGE2") == true
                ? Payload.page([3], next: nil, end: true, total: 3)
                : Payload.page([1, 2], next: "PAGE2", end: false, total: 3, top: 9)
        }
        let model = makeModel(http)

        await model.loadMore()
        XCTAssertEqual(model.comments.map(\.rpid), [1, 2])
        XCTAssertEqual(model.pinned?.rpid, 9)
        XCTAssertEqual(model.pinned?.isPinned, true)
        XCTAssertEqual(model.total, 3)
        XCTAssertFalse(model.isEnd)

        await model.loadMore()
        let requests = http.requests(to: listPath)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(query(requests[0])["pagination_str"], #"{"offset":""}"#)
        XCTAssertEqual(query(requests[1])["pagination_str"], #"{"offset":"PAGE2"}"#)
        XCTAssertEqual(model.comments.map(\.rpid), [1, 2, 3])
        XCTAssertEqual(model.pinned?.rpid, 9, "a later page carries no pinned comment and must not clear it")
        XCTAssertTrue(model.isEnd)

        await model.loadMore()
        XCTAssertEqual(http.requests(to: listPath).count, 2, "nothing is asked for after the end")
    }

    func testSortSwitchResetsTheList() async throws {
        let http = CommentsHTTP()
        http.list = { query in
            query["mode"] == "2"
                ? Payload.page([7, 8], next: nil, end: true, total: 2)
                : Payload.page([1, 2], next: "PAGE2", end: false, total: 40, top: 9)
        }
        let model = makeModel(http)
        await model.loadMore()
        XCTAssertEqual(model.sort, .hot)

        await model.setSort(.time)
        XCTAssertEqual(model.sort, .time)
        XCTAssertEqual(model.comments.map(\.rpid), [7, 8])
        XCTAssertNil(model.pinned)
        XCTAssertEqual(model.total, 2)
        XCTAssertTrue(model.isEnd)
        let last = try XCTUnwrap(http.requests(to: listPath).last)
        XCTAssertEqual(query(last)["mode"], "2")
        XCTAssertEqual(query(last)["pagination_str"], #"{"offset":""}"#, "a new sort starts from the first page")
    }

    func testClosedCommentsShowTheMessage() async throws {
        let http = CommentsHTTP()
        http.list = { _ in #"{"code":12061,"message":"UP主已关闭评论区","ttl":1}"# }
        let model = makeModel(http)

        await model.loadMore()
        XCTAssertEqual(model.closedMessage, "UP主已关闭评论区")
        XCTAssertNil(model.error)
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertFalse(model.loading)

        await model.loadMore()
        XCTAssertEqual(http.requests(to: listPath).count, 1, "a closed section is not asked again")
    }

    func testLikeIsOptimisticAndRollsBack() async throws {
        let http = CommentsHTTP()
        http.list = { _ in Payload.page([1, 2], next: nil, end: true, total: 2) }
        http.gated = likePath
        http.post = { _ in #"{"code":12015,"message":"点赞过于频繁","ttl":1}"# }
        var logins = 0
        let model = makeModel(http, requestLogin: { logins += 1 })
        await model.loadMore()
        let comment = try XCTUnwrap(model.comments.first)
        XCTAssertEqual(comment.likes, 10)

        let like = Task { await model.toggleLike(comment) }
        let reached = await waitUntil { http.gate.waiting > 0 }
        XCTAssertTrue(reached, "the like request never went out")
        XCTAssertEqual(model.comments[0].likes, 11, "the count moves before the server answers")
        XCTAssertEqual(model.comments[0].action, 1)

        http.gate.open()
        await like.value
        XCTAssertEqual(model.comments[0].likes, 10)
        XCTAssertEqual(model.comments[0].action, 0)
        XCTAssertEqual(model.toast, "点赞过于频繁")
        XCTAssertEqual(logins, 0)
        let body = String(decoding: http.requests(to: likePath).first?.body ?? Data(), as: UTF8.self)
        for field in ["oid=\(Payload.aid)", "type=1", "rpid=1", "action=1", "csrf=T"] {
            XCTAssertTrue(body.contains(field), "\(field) missing from \(body)")
        }
    }

    func testThreadLoadsAndPages() async throws {
        let http = CommentsHTTP()
        http.list = { _ in Payload.page([1], next: nil, end: true, total: 1) }
        http.thread = { query in
            query["pn"] == "1"
                ? Payload.thread(root: 1, replies: Array(101...120), page: 1, count: 25)
                : Payload.thread(root: 1, replies: Array(121...125), page: 2, count: 25)
        }
        let model = makeModel(http)
        await model.loadMore()
        let root = try XCTUnwrap(model.comments.first)

        await model.openThread(root)
        XCTAssertEqual(model.thread?.root.rpid, 1)
        XCTAssertEqual(model.thread?.replies.count, 20)
        XCTAssertEqual(model.thread?.total, 25)
        XCTAssertEqual(model.thread?.sort, .time)
        XCTAssertEqual(model.thread?.isEnd, false)
        let first = try XCTUnwrap(http.requests(to: threadPath).first)
        XCTAssertEqual(query(first)["root"], "1")
        XCTAssertEqual(query(first)["sort"], "0")

        await model.loadMoreThread()
        XCTAssertEqual(model.thread?.replies.map(\.rpid), Array(101...125))
        XCTAssertEqual(model.thread?.page, 2)
        XCTAssertEqual(model.thread?.isEnd, true)
        XCTAssertEqual(http.requests(to: threadPath).map { query($0)["pn"] }, ["1", "2"])

        await model.loadMoreThread()
        XCTAssertEqual(http.requests(to: threadPath).count, 2)

        model.closeThread()
        XCTAssertNil(model.thread)
    }

    func testDeleteRemovesTheRow() async throws {
        let http = CommentsHTTP()
        http.list = { _ in Payload.page([1, 2, 3], next: nil, end: true, total: 3) }
        http.post = { _ in #"{"code":0,"message":"0","ttl":1}"# }
        let model = makeModel(http)
        await model.loadMore()
        let target = try XCTUnwrap(model.comments.first { $0.rpid == 2 })

        await model.delete(target)
        XCTAssertEqual(model.comments.map(\.rpid), [1, 3])
        XCTAssertEqual(model.total, 2)
        let body = String(decoding: http.requests(to: deletePath).first?.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("rpid=2"), body)
        XCTAssertTrue(body.contains("oid=\(Payload.aid)"), body)
    }

    func testLoggedOutReactionAsksForLoginWithoutARequest() async throws {
        let http = CommentsHTTP()
        http.list = { _ in Payload.page([1], next: nil, end: true, total: 1) }
        var logins = 0
        let model = makeModel(http, loggedIn: false, requestLogin: { logins += 1 })
        await model.loadMore()
        let comment = try XCTUnwrap(model.comments.first)

        await model.toggleLike(comment)
        await model.delete(comment)
        XCTAssertEqual(logins, 2)
        XCTAssertEqual(model.comments.first?.likes, 10)
        XCTAssertTrue(http.requests(to: likePath).isEmpty)
        XCTAssertTrue(http.requests(to: deletePath).isEmpty)
    }

    // MARK: helpers

    private func makeModel(_ http: CommentsHTTP, loggedIn: Bool = true, requestLogin: @escaping () -> Void = {}) -> CommentsModel {
        let client = BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
        return CommentsModel(client: client, aid: Payload.aid, upMid: 42, isLoggedIn: { loggedIn }, requestLogin: requestLogin)
    }

    private func query(_ request: HTTPRequest) -> [String: String] {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

/// Invented comment payloads, shaped like /x/v2/reply/wbi/main and /x/v2/reply/reply.
private enum Payload {
    static let aid: Int64 = 900_000_001

    static func comment(_ rpid: Int64, root: Int64 = 0) -> String {
        """
        {"rpid":\(rpid),"oid":\(aid),"type":1,"mid":2001,"root":\(root),"parent":\(root),"count":0,"rcount":3,"ctime":1760000000,
         "like":10,"action":0,
         "member":{"mid":"2001","uname":"测试用户\(rpid)","avatar":"","level_info":{"current_level":5},"vip":{"vipStatus":0}},
         "content":{"message":"第\(rpid)条评论"},"replies":null,"up_action":{"like":false},"reply_control":{}}
        """
    }

    static func page(_ rpids: [Int64], next: String?, end: Bool, total: Int, top: Int64? = nil) -> String {
        let pagination = next.map { #","pagination_reply":{"next_offset":"\#($0)"}"# } ?? ""
        let cursor = #"{"is_end":\#(end),"all_count":\#(total)\#(pagination)}"#
        let replies = rpids.map { comment($0) }.joined(separator: ",")
        let tops = top.map { comment($0) } ?? ""
        return #"{"code":0,"message":"0","ttl":1,"data":{"cursor":\#(cursor),"replies":[\#(replies)],"top_replies":[\#(tops)]}}"#
    }

    static func thread(root: Int64, replies: [Int64], page: Int, count: Int) -> String {
        let items = replies.map { comment($0, root: root) }.joined(separator: ",")
        return #"{"code":0,"message":"0","ttl":1,"data":{"page":{"num":\#(page),"size":20,"count":\#(count)},"root":\#(comment(root)),"replies":[\#(items)]}}"#
    }
}

/// Answers the comment endpoints from closures, and can hold one path until the test opens its gate.
private final class CommentsHTTP: FixtureHTTP, @unchecked Sendable {
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        var waiting: Int { lock.withLock { waiters.count } }

        func wait() async {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock { () -> Bool in
                    if isOpen { return true }
                    waiters.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }

        func open() {
            let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                isOpen = true
                defer { waiters = [] }
                return waiters
            }
            waiting.forEach { $0.resume() }
        }
    }

    var list: ([String: String]) -> String = { _ in Payload.page([], next: nil, end: true, total: 0) }
    var thread: ([String: String]) -> String = { _ in #"{"code":-404,"message":"啥都木有","ttl":1}"# }
    var post: (String) -> String = { _ in #"{"code":0,"message":"0","ttl":1}"# }
    var gated: String?
    let gate = Gate()

    override func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.path == gated { await gate.wait() }
        return try await super.send(request)
    }

    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        switch request.url.path {
        case "/x/v2/reply/wbi/main", "/x/v2/reply/main":
            return (200, Data(list(query).utf8))
        case "/x/v2/reply/reply":
            return (200, Data(thread(query).utf8))
        case "/x/v2/reply/action", "/x/v2/reply/hate", "/x/v2/reply/del":
            return (200, Data(post(request.url.path).utf8))
        default:
            return super.answer(request)
        }
    }
}
