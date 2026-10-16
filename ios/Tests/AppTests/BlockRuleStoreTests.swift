import XCTest
import BiliAPI
import Danmaku
@testable import BiliNative

@MainActor
final class BlockRuleStoreTests: XCTestCase {
    private let rulesPath = "/x/dm/filter/user"
    private let addPath = "/x/dm/filter/user/add"
    private let delPath = "/x/dm/filter/user/del"
    private let spiPath = "/x/frontend/finger/spi"

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private struct Rig {
        let store: BlockRuleStore
        let http: FixtureHTTP
        let cookies: CookieJar
        let clock: Clock
    }

    private func makeRig(loggedIn: Bool = true, http: FixtureHTTP = FixtureHTTP()) -> Rig {
        var jar = ["buvid3": "b3", "buvid4": "b4"]
        if loggedIn { jar.merge(["SESSDATA": "s", "bili_jct": "T"]) { $1 } }
        let cookies = CookieJar(jar)
        let clock = Clock()
        let client = BiliClient(transport: http, cookies: cookies)
        return Rig(store: BlockRuleStore(client: client, now: { clock.now }), http: http, cookies: cookies, clock: clock)
    }

    private func body(of request: HTTPRequest?) -> String {
        String(decoding: request?.body ?? Data(), as: UTF8.self)
    }

    func testRefreshIsCachedForTenMinutes() async {
        let rig = makeRig()
        await rig.store.refresh()
        XCTAssertEqual(rig.store.rules.count, 4)
        rig.clock.now += 300
        await rig.store.refresh()
        XCTAssertEqual(rig.http.requests(to: rulesPath).count, 1)
        rig.clock.now += 360
        await rig.store.refresh()
        XCTAssertEqual(rig.http.requests(to: rulesPath).count, 2)
    }

    func testForcedRefreshSkipsTheCache() async {
        let rig = makeRig()
        await rig.store.refresh()
        await rig.store.refresh(force: true)
        XCTAssertEqual(rig.http.requests(to: rulesPath).count, 2)
    }

    func testLoggedOutGivesNoRulesAndNoRequest() async {
        let rig = makeRig(loggedIn: false)
        await rig.store.refresh()
        XCTAssertTrue(rig.store.rules.isEmpty)
        XCTAssertTrue(rig.http.requests(to: rulesPath).isEmpty)
        XCTAssertTrue(rig.http.requests(to: spiPath).isEmpty)
    }

    func testLoggingOutEmptiesTheRulesWithoutAskingAgain() async {
        let rig = makeRig()
        await rig.store.refresh()
        XCTAssertFalse(rig.store.rules.isEmpty)
        rig.cookies.removeAll()
        await rig.store.refresh()
        XCTAssertTrue(rig.store.rules.isEmpty)
        XCTAssertEqual(rig.http.requests(to: rulesPath).count, 1)
    }

    func testExpiredLoginGivesNoRules() async {
        let rig = makeRig(http: ExpiredHTTP())
        await rig.store.refresh()
        XCTAssertTrue(rig.store.rules.isEmpty)
        XCTAssertEqual(rig.http.requests(to: rulesPath).count, 1)
    }

    func testClearForgetsTheRulesAndTheCache() async {
        let rig = makeRig()
        await rig.store.refresh()
        rig.store.clear()
        XCTAssertTrue(rig.store.rules.isEmpty)
        await rig.store.refresh()
        XCTAssertEqual(rig.http.requests(to: rulesPath).count, 2)
        XCTAssertEqual(rig.store.rules.count, 4)
    }

    func testAddingAUserConvertsTheUidToItsHash() async throws {
        let rig = makeRig()
        try await rig.store.add(.user, filter: "12345")
        let sent = body(of: rig.http.requests(to: addPath).first)
        XCTAssertTrue(sent.contains("filter=\(MidHash.of(uid: 12345))"), sent)
        XCTAssertTrue(sent.contains("type=2"), sent)
        XCTAssertEqual(rig.store.rules.last, BlockRule(id: 9001, kind: .user, filter: MidHash.of(uid: 12345)))
    }

    func testAddingAKeywordSendsItTrimmed() async throws {
        let rig = makeRig()
        try await rig.store.add(.keyword, filter: "  剧透 ")
        let sent = body(of: rig.http.requests(to: addPath).first)
        XCTAssertTrue(sent.contains("type=0"), sent)
        XCTAssertTrue(sent.contains("filter=%E5%89%A7%E9%80%8F"), sent)
        XCTAssertEqual(rig.store.rules.last?.filter, "剧透")
    }

    func testAnEmptyOrUnreadableRuleIsRefusedWithoutARequest() async {
        let rig = makeRig()
        do {
            try await rig.store.add(.keyword, filter: "   ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BlockRuleStore.RuleError, .empty)
        }
        do {
            try await rig.store.add(.user, filter: "not a uid")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BlockRuleStore.RuleError, .invalidUser)
        }
        XCTAssertTrue(rig.http.requests(to: addPath).isEmpty)
    }

    func testAddingARuleTwiceIsRefusedWithoutASecondRequest() async throws {
        let rig = makeRig()
        await rig.store.refresh()
        do {
            try await rig.store.add(.keyword, filter: "剧透")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BlockRuleStore.RuleError, .duplicate)
        }
        XCTAssertTrue(rig.http.requests(to: addPath).isEmpty)
    }

    func testOpeningAVideoPageRefreshesTheRulesAndTheDanmakuFilterFollowsThem() async throws {
        let rig = makeRig()
        let suite = "block-rules-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BiliClient(transport: rig.http, cookies: rig.cookies)
        let model = VideoPageModel(route: VideoRoute(bvid: VideoPageFixtures.bvidA, startSeconds: 0), client: client,
                                   settings: AppSettings(defaults: UserDefaults(suiteName: suite)!), blockRules: rig.store,
                                   account: { .loggedOut }, makeController: { FakePlayback(item: $0, player: $1) })
        await model.load()
        try await waitUntil { model.danmaku.rules.count == 4 }
        XCTAssertEqual(rig.http.requests(to: rulesPath).count, 1)
        try await rig.store.add(.keyword, filter: "新词")
        try await waitUntil { model.danmaku.rules.count == 5 }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func testDeleteSendsTheIdAndDropsTheRule() async throws {
        let rig = makeRig()
        await rig.store.refresh()
        let doomed = try XCTUnwrap(rig.store.rules.first)
        try await rig.store.delete(doomed)
        XCTAssertTrue(body(of: rig.http.requests(to: delPath).first).contains("ids=\(doomed.id)"))
        XCTAssertFalse(rig.store.rules.contains(doomed))
        XCTAssertEqual(rig.store.rules.count, 3)
    }
}

private final class ExpiredHTTP: FixtureHTTP {
    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard request.url.path == "/x/dm/filter/user" else { return super.answer(request) }
        return (200, Data(#"{"code":-101,"message":"账号未登录"}"#.utf8))
    }
}
