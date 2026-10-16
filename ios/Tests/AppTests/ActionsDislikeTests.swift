import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class ActionsDislikeTests: XCTestCase {
    private let dislikePath = "/x/v2/view/dislike"
    private let ok = #"{"code":0,"message":"0","ttl":1,"data":null}"#

    private final class State {
        var toasts: [String] = []
        var logins = 0
        var token: String?
        var cleared = 0
    }

    private struct Rig {
        let model: ActionsModel
        let http: ScriptedHTTP
        let state: State
    }

    func testWithoutKeysTheButtonIsGreyAndTheTapExplains() async {
        let rig = makeRig(signer: nil, token: "tok")
        XCTAssertFalse(rig.model.dislikeAvailable)
        await rig.model.toggleDislike()
        XCTAssertEqual(rig.state.toasts, ["此版本不支持不喜欢"])
        XCTAssertFalse(rig.model.needsAppToken)
        XCTAssertFalse(rig.model.disliked)
        XCTAssertEqual(rig.http.total, 0)
    }

    func testWithoutATokenItOpensTheSheetAndSendsNothing() async {
        let rig = makeRig(token: nil)
        XCTAssertTrue(rig.model.dislikeAvailable)
        await rig.model.toggleDislike()
        XCTAssertTrue(rig.model.needsAppToken)
        XCTAssertFalse(rig.model.disliked)
        XCTAssertEqual(rig.http.total, 0)
        XCTAssertTrue(rig.state.toasts.isEmpty)
    }

    func testLoggedOutAsksForLoginBeforeAnything() async {
        let rig = makeRig(token: nil, loggedIn: false)
        await rig.model.toggleDislike()
        XCTAssertEqual(rig.state.logins, 1)
        XCTAssertFalse(rig.model.needsAppToken)
        XCTAssertEqual(rig.http.total, 0)
    }

    func testDislikeSendsTheTokenSignedWithoutCookiesAndTakesTheLikeBack() async {
        let rig = makeRig(token: "tok-1", relation: VideoRelation(like: true, dislike: false, favorite: false, attention: false, coins: 0))
        await rig.model.toggleDislike()
        XCTAssertTrue(rig.model.disliked)
        XCTAssertFalse(rig.model.liked)
        XCTAssertEqual(rig.model.likeCount, 9130)
        let request = rig.http.requests(to: dislikePath)
        XCTAssertEqual(request.count, 1)
        XCTAssertEqual(request.first?.url.host, "app.bilibili.com")
        XCTAssertNil(request.first?.headers["Cookie"])
        let body = rig.http.body(of: dislikePath)
        for field in ["access_key=tok-1", "aid=900000001", "dislike=0", "appkey=testkey", "sign="] {
            XCTAssertTrue(body.contains(field), "\(field) missing from \(body)")
        }
        XCTAssertFalse(body.contains("csrf"))

        await rig.model.toggleDislike()
        XCTAssertFalse(rig.model.disliked)
        XCTAssertTrue(rig.http.body(of: dislikePath, at: 1).contains("dislike=1"))
        XCTAssertEqual(rig.state.cleared, 0)
        XCTAssertTrue(rig.state.toasts.isEmpty)
    }

    func testAnInvalidTokenIsDroppedAndTheSheetOpensAgain() async {
        for code in [-101, -2] {
            let rig = makeRig(token: "stale", reply: #"{"code":\#(code),"message":"invalid"}"#)
            await rig.model.toggleDislike()
            XCTAssertFalse(rig.model.disliked, "\(code)")
            XCTAssertNil(rig.state.token, "\(code)")
            XCTAssertEqual(rig.state.cleared, 1, "\(code)")
            XCTAssertTrue(rig.model.needsAppToken, "\(code)")
            XCTAssertEqual(rig.state.logins, 0, "an app token is not the web login")
            XCTAssertTrue(rig.state.toasts.isEmpty, "\(code)")
        }
    }

    func testOtherRefusalsKeepTheTokenAndToastTheServerMessage() async {
        let rig = makeRig(token: "tok-1", reply: #"{"code":65006,"message":"操作失败"}"#)
        await rig.model.toggleDislike()
        XCTAssertFalse(rig.model.disliked)
        XCTAssertEqual(rig.state.token, "tok-1")
        XCTAssertFalse(rig.model.needsAppToken)
        XCTAssertEqual(rig.state.toasts, ["操作失败"])
    }

    func testLikingAfterDislikingClearsTheDislike() async {
        let rig = makeRig(token: "tok-1", relation: VideoRelation(like: false, dislike: true, favorite: false, attention: false, coins: 0))
        XCTAssertTrue(rig.model.disliked)
        await rig.model.toggleLike()
        XCTAssertFalse(rig.model.disliked)
    }

    private func makeRig(signer: AppSigner? = TVLoginFixtures.signer, token: String?, loggedIn: Bool = true,
                         reply: String? = nil, relation: VideoRelation? = nil) -> Rig {
        let http = ScriptedHTTP([dislikePath: [reply ?? ok]])
        let state = State()
        state.token = token
        let detail = VideoDetail(bvid: VideoPageFixtures.bvidA, aid: VideoPageFixtures.aidA, title: "演示", cover: "", pubdate: 0,
                                 duration: 200, desc: "", descParts: [], copyright: 1,
                                 owner: VideoOwner(mid: 42, name: "演示UP主", face: ""),
                                 stat: VideoStat(view: 37000, danmaku: 337, reply: 213, favorite: 3907, coin: 1210, share: 148, like: 9131),
                                 pages: [], season: nil, staff: [], width: 1920, height: 1080, honor: nil, redirectURL: nil)
        let model = ActionsModel(client: TVLoginFixtures.client(http), detail: detail, relation: relation, uploader: nil,
                                 isLoggedIn: { loggedIn }, requestLogin: { state.logins += 1 },
                                 toast: { state.toasts.append($0) }, signer: signer,
                                 loadAppToken: { state.token },
                                 clearAppToken: {
                                     state.token = nil
                                     state.cleared += 1
                                 })
        return Rig(model: model, http: http, state: state)
    }
}
