import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class ComposerModelTests: XCTestCase {
    private let addPath = "/x/v2/reply/add"
    private let aid: Int64 = 900_000_002

    func testTopLevelPostSendsNoRootOrParent() async throws {
        let http = ComposerHTTP()
        let comments = makeComments(http)
        let composer = makeComposer(http, target: .video, comments: comments)
        XCTAssertEqual(composer.placeholder, "哎呦，不错哦，发条评论吧")

        composer.text = "第一条 & 1+1=2 😀"
        let posted = await composer.post()

        XCTAssertTrue(posted)
        let form = try XCTUnwrap(fields(http.requests(to: addPath).first))
        XCTAssertEqual(form["message"], "第一条 & 1+1=2 😀")
        XCTAssertEqual(form["oid"], String(aid))
        XCTAssertEqual(form["type"], "1")
        XCTAssertEqual(form["csrf"], "T")
        XCTAssertNil(form["root"])
        XCTAssertNil(form["parent"])
        XCTAssertNil(form["sync_to_dynamic"])
        XCTAssertEqual(comments.comments.first?.rpid, ComposerHTTP.postedRpid, "the new comment goes to the top of the list")
        XCTAssertEqual(composer.text, "", "the draft is cleared")
    }

    func testReplyToACommentUsesItForRootAndParent() async throws {
        let http = ComposerHTTP()
        http.postedRoot = 10
        let comments = makeComments(http)
        let target = comment(10, name: "小红")
        let composer = makeComposer(http, target: .comment(target), comments: comments)
        XCTAssertEqual(composer.placeholder, "回复 小红:")

        composer.text = "好"
        composer.syncToDynamic = true
        let posted = await composer.post()

        XCTAssertTrue(posted)
        let form = try XCTUnwrap(fields(http.requests(to: addPath).first))
        XCTAssertEqual(form["message"], "好")
        XCTAssertEqual(form["root"], "10")
        XCTAssertEqual(form["parent"], "10")
        XCTAssertEqual(form["sync_to_dynamic"], "1")
    }

    func testReplyInsideAThreadPrefixesTheNameAndSplitsRootAndParent() async throws {
        let http = ComposerHTTP()
        http.postedRoot = 10
        http.thread = { _ in ComposerPayload.thread(root: 10, replies: [11]) }
        let comments = makeComments(http)
        let root = comment(10, name: "小红")
        await comments.openThread(root)
        let reply = try XCTUnwrap(comments.thread?.replies.first)
        let composer = makeComposer(http, target: .threadReply(root: root, reply: reply), comments: comments)
        XCTAssertEqual(composer.placeholder, "回复 小明:")

        composer.text = "好"
        let posted = await composer.post()

        XCTAssertTrue(posted)
        let form = try XCTUnwrap(fields(http.requests(to: addPath).first))
        XCTAssertEqual(form["message"], "回复 @小明 :好")
        XCTAssertEqual(form["root"], "10")
        XCTAssertEqual(form["parent"], "11")
        XCTAssertEqual(comments.thread?.replies.first?.rpid, ComposerHTTP.postedRpid, "the reply goes to the top of the thread")
    }

    func testFailedPostKeepsTheDraft() async throws {
        let http = ComposerHTTP()
        http.post = #"{"code":12015,"message":"评论发送过于频繁","ttl":1}"#
        var logins = 0
        let comments = makeComments(http, requestLogin: { logins += 1 })
        let composer = makeComposer(http, target: .video, comments: comments)

        composer.text = "留着我"
        let posted = await composer.post()

        XCTAssertFalse(posted)
        XCTAssertEqual(composer.text, "留着我")
        XCTAssertEqual(comments.toast, "评论发送过于频繁")
        XCTAssertTrue(comments.comments.isEmpty)
        XCTAssertEqual(logins, 0)

        // Closing and reopening the composer for the same target brings the draft back; another target has its own.
        let again = makeComposer(http, target: .video, comments: comments)
        XCTAssertEqual(again.text, "留着我")
        let other = makeComposer(http, target: .comment(comment(10, name: "小红")), comments: comments)
        XCTAssertEqual(other.text, "")
    }

    func testRecentEmotesAreMostRecentFirstAndCapped() throws {
        let suite = "ComposerModelTests.recent"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(RecentEmotes.list(defaults: defaults).isEmpty)

        for index in 0..<20 {
            RecentEmotes.record(Emote(token: "[e\(index)]", url: "https://example.invalid/\(index).png", large: false), defaults: defaults)
        }
        RecentEmotes.record(Emote(token: "[e10]", url: "https://example.invalid/10.png", large: false), defaults: defaults)

        let recent = RecentEmotes.list(defaults: defaults)
        XCTAssertEqual(recent.count, 14)
        XCTAssertEqual(recent.first?.token, "[e10]", "using one again moves it to the front")
        XCTAssertEqual(recent.map(\.token), ["[e10]", "[e19]", "[e18]", "[e17]", "[e16]", "[e15]", "[e14]", "[e13]", "[e12]",
                                             "[e11]", "[e9]", "[e8]", "[e7]", "[e6]"])
        XCTAssertEqual(recent.first?.url, "https://example.invalid/10.png")
        XCTAssertNotNil(defaults.data(forKey: "emotes.recent"))
    }

    // MARK: helpers

    private func client(_ http: ComposerHTTP) -> BiliClient {
        BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
    }

    private func makeComments(_ http: ComposerHTTP, requestLogin: @escaping () -> Void = {}) -> CommentsModel {
        CommentsModel(client: client(http), aid: aid, upMid: 42, isLoggedIn: { true }, requestLogin: requestLogin)
    }

    private func makeComposer(_ http: ComposerHTTP, target: ReplyTarget, comments: CommentsModel) -> ComposerModel {
        ComposerModel(client: client(http), aid: aid, target: target, comments: comments)
    }

    private func comment(_ rpid: Int64, name: String) -> Comment {
        Comment(rpid: rpid, oid: aid, mid: 3000 + rpid, member: CommentMember(mid: 3000 + rpid, name: name), message: "第\(rpid)条")
    }

    private func fields(_ request: HTTPRequest?) -> [String: String]? {
        guard let body = request?.body else { return nil }
        var fields: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let name = parts.first?.removingPercentEncoding else { continue }
            fields[name] = parts.count > 1 ? parts[1].removingPercentEncoding : ""
        }
        return fields
    }
}

/// Invented payloads shaped like /x/v2/reply/add and /x/v2/reply/reply.
private enum ComposerPayload {
    static func comment(_ rpid: Int64, root: Int64, name: String, message: String) -> String {
        """
        {"rpid":\(rpid),"oid":900000002,"type":1,"mid":\(3000 + rpid),"root":\(root),"parent":\(root),"count":0,"rcount":0,
         "ctime":1760000000,"like":0,"action":0,
         "member":{"mid":"\(3000 + rpid)","uname":"\(name)","avatar":"","level_info":{"current_level":4},"vip":{"vipStatus":0}},
         "content":{"message":"\(message)"},"replies":null,"up_action":{"like":false},"reply_control":{}}
        """
    }

    static func thread(root: Int64, replies: [Int64]) -> String {
        let items = replies.map { comment($0, root: root, name: "小明", message: "第\($0)条") }.joined(separator: ",")
        let rootJSON = comment(root, root: 0, name: "小红", message: "第\(root)条")
        return #"{"code":0,"message":"0","ttl":1,"data":{"page":{"num":1,"size":20,"count":1},"root":\#(rootJSON),"replies":[\#(items)]}}"#
    }
}

/// Answers reply/add with a fixed new comment (under `postedRoot`), or with `post` when that is set.
private final class ComposerHTTP: FixtureHTTP, @unchecked Sendable {
    static let postedRpid: Int64 = 700

    var postedRoot: Int64 = 0
    var post: String?
    var thread: ([String: String]) -> String = { _ in #"{"code":-404,"message":"啥都木有","ttl":1}"# }

    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        switch request.url.path {
        case "/x/v2/reply/add":
            if let post { return (200, Data(post.utf8)) }
            let reply = ComposerPayload.comment(Self.postedRpid, root: postedRoot, name: "我", message: "新评论")
            return (200, Data(#"{"code":0,"message":"0","ttl":1,"data":{"rpid":700,"reply":\#(reply)}}"#.utf8))
        case "/x/v2/reply/reply":
            return (200, Data(thread(query).utf8))
        default:
            return super.answer(request)
        }
    }
}
