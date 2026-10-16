import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class ActionsModelTests: XCTestCase {
    private let likePath = "/x/web-interface/archive/like"
    private let triplePath = "/x/web-interface/archive/like/triple"
    private let followPath = "/x/relation/modify"

    func testLikeIsOptimisticAndClearsDislike() async {
        let gated = GatedHTTP()
        let rig = makeRig(http: gated, relation: VideoRelation(like: false, dislike: true, favorite: false, attention: false, coins: 0))
        XCTAssertTrue(rig.model.disliked)
        let pending = Task { await rig.model.toggleLike() }
        while rig.http.requests(to: likePath).isEmpty { await Task.yield() }
        // The change shows while the server has not answered yet.
        XCTAssertTrue(rig.model.liked)
        XCTAssertFalse(rig.model.disliked)
        XCTAssertEqual(rig.model.likeCount, 9132)
        gated.open()
        await pending.value
        XCTAssertTrue(rig.model.liked)
        let body = rig.http.body(of: likePath)
        XCTAssertTrue(body.contains("like=1"), body)
        XCTAssertTrue(body.contains("aid=900000001"), body)

        await rig.model.toggleLike()
        XCTAssertFalse(rig.model.liked)
        XCTAssertEqual(rig.model.likeCount, 9131)
        XCTAssertTrue(rig.http.body(of: likePath, at: 1).contains("like=2"))
        XCTAssertTrue(rig.toasts.isEmpty)
    }

    func testFailureRollsBackAndToastsTheServerMessage() async {
        let rig = makeRig(http: RefusingHTTP(code: 65006, message: "已赞过"),
                          relation: VideoRelation(like: false, dislike: true, favorite: false, attention: false, coins: 0))
        await rig.model.toggleLike()
        XCTAssertFalse(rig.model.liked)
        XCTAssertTrue(rig.model.disliked)
        XCTAssertEqual(rig.model.likeCount, 9131)
        XCTAssertEqual(rig.toasts, ["已赞过"])
        XCTAssertEqual(rig.logins.count, 0)
    }

    func testExpiredLoginRollsBackAndAsksForLogin() async {
        let rig = makeRig(http: RefusingHTTP(code: -101, message: "账号未登录"))
        await rig.model.toggleLike()
        XCTAssertFalse(rig.model.liked)
        XCTAssertEqual(rig.model.likeCount, 9131)
        XCTAssertEqual(rig.logins.count, 1)
        XCTAssertEqual(rig.toasts, ["需要登录"])
    }

    func testLoggedOutSendsNothingAndAsksForLogin() async {
        let rig = makeRig(loggedIn: false)
        await rig.model.toggleLike()
        await rig.model.triple()
        await rig.model.coin(1, alsoLike: true)
        await rig.model.applyFavourites(add: [3001], remove: [])
        await rig.model.toggleFollow()
        rig.model.ask(.coin)
        XCTAssertEqual(rig.logins.count, 6)
        XCTAssertNil(rig.model.prompt)
        XCTAssertFalse(rig.model.liked)
        XCTAssertEqual(rig.model.coins, 0)
        XCTAssertTrue(rig.http.posts.isEmpty)
        // Sharing needs no account: the sheet opens, the share is just not counted.
        rig.model.ask(.share)
        XCTAssertEqual(rig.model.prompt, .share)
        await rig.model.shared()
        XCTAssertEqual(rig.model.shareCount, 148)
        XCTAssertTrue(rig.http.posts.isEmpty)
    }

    func testTripleSetsAllThreeAndCounts() async {
        let rig = makeRig(relation: VideoRelation(like: true, dislike: false, favorite: false, attention: false, coins: 0))
        await rig.model.triple()
        XCTAssertEqual(rig.http.requests(to: triplePath).count, 1)
        XCTAssertTrue(rig.model.liked)
        XCTAssertTrue(rig.model.favorited)
        XCTAssertEqual(rig.model.coins, 2)
        // Already liked: only the favourite and the two coins are new.
        XCTAssertEqual(rig.model.likeCount, 9131)
        XCTAssertEqual(rig.model.favCount, 3908)
        XCTAssertEqual(rig.model.coinCount, 1212)
        XCTAssertEqual(rig.model.maxCoins, 0)
        XCTAssertTrue(rig.toasts.isEmpty)
    }

    func testTripleWhenAllDoneOnlyToasts() async {
        let rig = makeRig(relation: VideoRelation(like: true, dislike: false, favorite: true, attention: false, coins: 1))
        await rig.model.triple()
        XCTAssertEqual(rig.toasts, ["已三连"])
        XCTAssertTrue(rig.http.posts.isEmpty)
    }

    func testCoinLimits() {
        let repost = makeRig(copyright: 2)
        XCTAssertEqual(repost.model.maxCoins, 1)
        XCTAssertFalse(repost.model.canGive(2, balance: 10))
        XCTAssertTrue(repost.model.canGive(1, balance: 10))

        let oneGiven = makeRig(relation: VideoRelation(like: false, dislike: false, favorite: false, attention: false, coins: 1))
        XCTAssertEqual(oneGiven.model.maxCoins, 1)
        XCTAssertFalse(oneGiven.model.canGive(2, balance: 10))

        let original = makeRig()
        XCTAssertEqual(original.model.maxCoins, 2)
        XCTAssertTrue(original.model.canGive(2, balance: 2))
        XCTAssertFalse(original.model.canGive(2, balance: 1.5))
        XCTAssertTrue(original.model.canGive(1, balance: 1.5))
        XCTAssertFalse(original.model.canGive(1, balance: 0.5))
    }

    func testUnfollowAndFollowRequests() async {
        let rig = makeRig(relation: VideoRelation(like: false, dislike: false, favorite: false, attention: true, coins: 0))
        // 已关注 asks first; the view's confirm then calls toggleFollow.
        rig.model.tapFollow()
        XCTAssertEqual(rig.model.prompt, .unfollow)
        XCTAssertTrue(rig.http.posts.isEmpty)
        await rig.model.toggleFollow()
        XCTAssertFalse(rig.model.following)
        await rig.model.toggleFollow()
        XCTAssertTrue(rig.model.following)
        let bodies = [rig.http.body(of: followPath), rig.http.body(of: followPath, at: 1)]
        XCTAssertTrue(bodies[0].contains("act=2"), bodies[0])
        XCTAssertTrue(bodies[1].contains("act=1"), bodies[1])
        XCTAssertTrue(bodies[0].contains("fid=42"), bodies[0])
    }

    func testCoinAddsAndCanAlsoLike() async {
        let rig = makeRig()
        await rig.model.coin(1, alsoLike: true)
        XCTAssertEqual(rig.model.coins, 1)
        XCTAssertEqual(rig.model.coinCount, 1211)
        XCTAssertTrue(rig.model.liked)
        XCTAssertTrue(rig.http.body(of: "/x/web-interface/coin/add").contains("select_like=1"))
        await rig.model.coin(2, alsoLike: false)
        XCTAssertEqual(rig.toasts, ["最多还能投1个硬币"])
        await rig.model.coin(1, alsoLike: false)
        await rig.model.coin(1, alsoLike: false)
        XCTAssertEqual(rig.toasts, ["最多还能投1个硬币", "已投满2个硬币"])
        XCTAssertEqual(rig.http.requests(to: "/x/web-interface/coin/add").count, 2)
    }

    func testALateRelationDoesNotUndoATap() async {
        let rig = makeRig()
        await rig.model.toggleLike()
        rig.model.apply(VideoRelation(like: false, dislike: false, favorite: false, attention: false, coins: 0))
        XCTAssertTrue(rig.model.liked)
    }

    func testALateRelationStillFillsInWhatWasNotTapped() async {
        let rig = makeRig()
        await rig.model.toggleFollow()
        rig.model.apply(VideoRelation(like: true, dislike: false, favorite: true, attention: false, coins: 1))
        XCTAssertTrue(rig.model.following, "the late answer undid the follow")
        XCTAssertTrue(rig.model.liked)
        XCTAssertTrue(rig.model.favorited)
        XCTAssertEqual(rig.model.coins, 1)
        XCTAssertTrue(rig.model.tripleDone)
    }

    /// 点赞 and 关注 sit side by side in full screen: a like that fails must not take back a follow that went through.
    func testAFailedLikeLeavesAFollowInFlightAlone() async {
        let http = PathGatedHTTP(refused: [likePath])
        let rig = makeRig(http: http)
        let like = Task { await rig.model.toggleLike() }
        while http.requests(to: likePath).isEmpty { await Task.yield() }
        let follow = Task { await rig.model.toggleFollow() }
        while http.requests(to: followPath).isEmpty { await Task.yield() }
        XCTAssertTrue(rig.model.liked)
        XCTAssertTrue(rig.model.following)

        http.open(likePath)
        await like.value
        XCTAssertFalse(rig.model.liked)
        XCTAssertEqual(rig.model.likeCount, 9131)
        XCTAssertTrue(rig.model.following, "the like's rollback undid the follow")
        http.open(followPath)
        await follow.value
        XCTAssertTrue(rig.model.following)
        XCTAssertEqual(rig.toasts, ["已赞过"])
    }

    /// Both fail, the earlier first: the later one's rollback must not bring back the earlier one's change.
    func testTwoFailuresEachTakeBackOnlyTheirOwn() async {
        let http = PathGatedHTTP(refused: [likePath, followPath])
        let rig = makeRig(http: http)
        let like = Task { await rig.model.toggleLike() }
        while http.requests(to: likePath).isEmpty { await Task.yield() }
        let follow = Task { await rig.model.toggleFollow() }
        while http.requests(to: followPath).isEmpty { await Task.yield() }

        http.open(likePath)
        await like.value
        http.open(followPath)
        await follow.value
        XCTAssertFalse(rig.model.liked, "the follow's rollback brought the failed like back")
        XCTAssertEqual(rig.model.likeCount, 9131)
        XCTAssertFalse(rig.model.following)
    }

    func testFailedTripleRollsBackAndKeepsTheDislike() async {
        let rig = makeRig(http: RefusingHTTP(code: -352, message: "风控校验失败"),
                          relation: VideoRelation(like: false, dislike: true, favorite: false, attention: true, coins: 0))
        await rig.model.triple()
        XCTAssertFalse(rig.model.liked)
        XCTAssertTrue(rig.model.disliked)
        XCTAssertFalse(rig.model.favorited)
        XCTAssertTrue(rig.model.following)
        XCTAssertEqual(rig.model.likeCount, 9131)
        XCTAssertEqual(rig.model.favCount, 3907)
        XCTAssertEqual(rig.toasts.count, 1)
    }

    func testTripleSendsOnlyWhenItWouldGoOut() async {
        XCTAssertTrue(makeRig().model.tripleSends)
        XCTAssertFalse(makeRig(loggedIn: false).model.tripleSends)
        let done = makeRig(relation: VideoRelation(like: true, dislike: false, favorite: true, attention: false, coins: 2))
        XCTAssertFalse(done.model.tripleSends)
    }

    func testShareLinkNamesThePartAfterTheFirst() {
        XCTAssertEqual(ShareLinks.video("BV1Dm4y1A7aa").absoluteString, "https://www.bilibili.com/video/BV1Dm4y1A7aa")
        XCTAssertEqual(ShareLinks.video("BV1Dm4y1A7aa", part: 1).absoluteString, "https://www.bilibili.com/video/BV1Dm4y1A7aa")
        XCTAssertEqual(ShareLinks.video("BV1Dm4y1A7aa", part: 2).absoluteString, "https://www.bilibili.com/video/BV1Dm4y1A7aa?p=2")
    }

    // MARK: helpers

    private final class Recorder {
        var toasts: [String] = []
        var logins: [Void] = []
    }

    private struct Rig {
        let model: ActionsModel
        let http: FixtureHTTP
        let recorder: Recorder
        var toasts: [String] { recorder.toasts }
        var logins: [Void] { recorder.logins }
    }

    /// Holds every POST until `open`, so a test can look at the page while the server has not answered.
    private final class GatedHTTP: FixtureHTTP, @unchecked Sendable {
        private let gate = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)

        func open() {
            gate.continuation.finish()
        }

        override func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let response = try await super.send(request)
            if request.method == "POST" {
                for await _ in gate.stream {}
            }
            return response
        }
    }

    /// Holds each POST until its path is opened, and refuses the paths in `refused` with 已赞过.
    private final class PathGatedHTTP: FixtureHTTP, @unchecked Sendable {
        private let refused: Set<String>
        private let lock = NSLock()
        private var gates: [String: AsyncStream<Void>.Continuation] = [:]
        private var streams: [String: AsyncStream<Void>] = [:]

        init(refused: Set<String>) {
            self.refused = refused
            super.init()
        }

        func open(_ path: String) {
            gate(path).continuation.finish()
        }

        private func gate(_ path: String) -> (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation) {
            lock.withLock {
                if let stream = streams[path], let continuation = gates[path] { return (stream, continuation) }
                let made = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
                streams[path] = made.stream
                gates[path] = made.continuation
                return made
            }
        }

        override func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let response = try await super.send(request)
            if request.method == "POST" {
                for await _ in gate(request.url.path).stream {}
            }
            return response
        }

        override func answer(_ request: HTTPRequest) -> (Int, Data) {
            guard request.method == "POST", refused.contains(request.url.path) else { return super.answer(request) }
            return (200, Data(#"{"code":65006,"message":"已赞过","ttl":1}"#.utf8))
        }
    }

    private final class RefusingHTTP: FixtureHTTP, @unchecked Sendable {
        let code: Int
        let message: String

        init(code: Int, message: String) {
            self.code = code
            self.message = message
            super.init()
        }

        override func answer(_ request: HTTPRequest) -> (Int, Data) {
            guard request.method == "POST" else { return super.answer(request) }
            return (200, Data(#"{"code":\#(code),"message":"\#(message)","ttl":1}"#.utf8))
        }
    }

    private func makeRig(http: FixtureHTTP = FixtureHTTP(), loggedIn: Bool = true, copyright: Int = 1,
                         relation: VideoRelation? = nil) -> Rig {
        let client = BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
        let detail = VideoDetail(bvid: VideoPageFixtures.bvidA, aid: VideoPageFixtures.aidA, title: "演示", cover: "", pubdate: 0,
                                 duration: 200, desc: "", descParts: [], copyright: copyright,
                                 owner: VideoOwner(mid: 42, name: "演示UP主", face: ""),
                                 stat: VideoStat(view: 37000, danmaku: 337, reply: 213, favorite: 3907, coin: 1210, share: 148, like: 9131),
                                 pages: [], season: nil, staff: [], width: 1920, height: 1080, honor: nil, redirectURL: nil)
        let recorder = Recorder()
        let model = ActionsModel(client: client, detail: detail, relation: relation, uploader: nil,
                                 isLoggedIn: { loggedIn }, requestLogin: { recorder.logins.append(()) },
                                 toast: { recorder.toasts.append($0) })
        return Rig(model: model, http: http, recorder: recorder)
    }
}

private extension FixtureHTTP {
    var posts: [HTTPRequest] {
        ["/x/web-interface/archive/like", "/x/web-interface/archive/like/triple", "/x/web-interface/coin/add",
         "/x/v3/fav/resource/batch-deal", "/x/relation/modify", "/x/web-interface/share/add"].flatMap { requests(to: $0) }
    }

    func body(of path: String, at index: Int = 0) -> String {
        let found = requests(to: path)
        guard found.indices.contains(index) else { return "" }
        return String(decoding: found[index].body ?? Data(), as: UTF8.self)
    }
}
