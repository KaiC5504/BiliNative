import AVFoundation
import XCTest
import AppLogic
import BiliAPI
@testable import BiliNative

@MainActor
final class VideoPageModelTests: XCTestCase {
    private typealias F = VideoPageFixtures
    private let heartbeatPath = "/x/click-interface/web/heartbeat"

    func testLoadResumesAtTheSavedPositionForTheSamePart() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1), resume: (65_000, F.cidA1))
        await page.model.load()
        let fake = try XCTUnwrap(page.fakes.all.first)
        XCTAssertEqual(fake.starts.map(\.time), [0])
        XCTAssertEqual(fake.starts.map(\.autoplay), [false])
        XCTAssertEqual(fake.seeks, [65])
        XCTAssertTrue(fake.isPlaying)
        XCTAssertEqual(page.model.current, PlayItem(bvid: F.bvidA, cid: F.cidA1))
    }

    func testResumeForAnotherPartStartsAtZero() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1), resume: (65_000, F.cidA2))
        await page.model.load()
        let fake = try XCTUnwrap(page.fakes.all.first)
        XCTAssertEqual(fake.seeks, [])
        XCTAssertTrue(fake.isPlaying)
    }

    func testRouteStartOverridesResume() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 12), resume: (65_000, F.cidA1))
        await page.model.load()
        let fake = try XCTUnwrap(page.fakes.all.first)
        XCTAssertEqual(fake.starts.map(\.time), [12])
        XCTAssertEqual(fake.starts.map(\.autoplay), [true])
        XCTAssertEqual(fake.seeks, [])
    }

    func testWithoutACidThePageOpensThePartLastPlayed() async {
        let page = makePage(VideoRoute(bvid: F.bvidA))
        await page.model.load()
        XCTAssertEqual(page.model.current, PlayItem(bvid: F.bvidA, cid: F.lastPlayCid))
        XCTAssertEqual(page.model.detail?.pages.count, 2)
    }

    func testEndPlaysTheNextEpisodeInPlaceAndKeepsTheRate() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA2, startSeconds: 0))
        await page.model.load()
        page.model.rate = 2
        await page.model.handleEnd()
        XCTAssertEqual(page.model.detail?.bvid, F.bvidB)
        XCTAssertEqual(page.model.current, PlayItem(bvid: F.bvidB, cid: F.cidB))
        XCTAssertEqual(page.model.route.bvid, F.bvidA)
        XCTAssertEqual(page.fakes.all.count, 2)
        XCTAssertTrue(page.fakes.all[0].stopped)
        XCTAssertEqual(page.fakes.all[1].rate, 2)
        XCTAssertFalse(page.model.ended)
    }

    func testEndOfAPartPlaysTheNextPart() async {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        await page.model.load()
        await page.model.handleEnd()
        XCTAssertEqual(page.model.current, PlayItem(bvid: F.bvidA, cid: F.cidA2))
        XCTAssertEqual(page.http.requests(to: "/x/web-interface/wbi/view").count, 1)
    }

    func testEndOfTheLastEpisodeShowsTheEndScreen() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidC, startSeconds: 0))
        await page.model.load()
        await page.model.handleEnd()
        XCTAssertTrue(page.model.ended)
        XCTAssertEqual(page.fakes.all.count, 1)
        XCTAssertEqual(page.fakes.all.first?.starts.count, 1)
    }

    func testHeartbeatsOnlyWhenLoggedIn() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        await page.model.load()
        let fake = try XCTUnwrap(page.fakes.all.first)
        fake.isPlaying = true
        fake.tick(16)
        fake.tick(32)
        page.model.pause()
        await page.model.settleHeartbeats()
        XCTAssertTrue(page.http.requests(to: heartbeatPath).isEmpty)

        page.account.value = .loggedIn(name: "测试", vip: false)
        fake.isPlaying = true
        fake.tick(48)
        await page.model.settleHeartbeats()
        let sent = page.http.requests(to: heartbeatPath)
        XCTAssertEqual(sent.count, 1)
        let body = String(decoding: sent.first?.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("played_time=48"), body)
        XCTAssertTrue(body.contains("cid=\(F.cidA1)"), body)
    }

    func testFinishedHeartbeatIsNotOverwrittenByLeaving() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidC, startSeconds: 0), loggedIn: true)
        await page.model.load()
        page.model.appear()
        let fake = try XCTUnwrap(page.fakes.all.first)
        fake.position = 199
        await page.model.handleEnd()
        page.model.disappear()
        await page.model.settleHeartbeats()
        let played = page.http.requests(to: heartbeatPath).map { String(decoding: $0.body ?? Data(), as: UTF8.self) }
        XCTAssertEqual(played.last?.contains("played_time=-1"), true, "\(played)")
    }

    func testCoveredPageStopsItsController() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        await page.model.load()
        page.model.appear()
        let fake = try XCTUnwrap(page.fakes.all.first)
        fake.position = 30
        page.model.disappear()
        XCTAssertTrue(fake.stopped)
        page.model.appear()
        try await waitUntil { fake.starts.count == 2 }
        XCTAssertEqual(fake.starts.last?.time, 30)
        XCTAssertEqual(fake.starts.last?.autoplay, false)
        XCTAssertEqual(page.fakes.all.count, 1)
    }

    func testSleepTimerPausesAtTheDeadline() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0), sleep: { _ in })
        await page.model.load()
        let fake = try XCTUnwrap(page.fakes.all.first)
        XCTAssertTrue(fake.isPlaying)
        page.model.setSleepTimer(minutes: 15)
        XCTAssertNotNil(page.model.sleepDeadline)
        try await waitUntil { fake.paused }
        XCTAssertNil(page.model.sleepDeadline)
    }

    func testRedirectedVideoShowsAFailureInsteadOfPlaying() async {
        let page = makePage(VideoRoute(bvid: "BV1Redirect01"), transport: RedirectingHTTP())
        await page.model.load()
        XCTAssertEqual(page.model.loadError, "暂不支持播放此类视频")
        XCTAssertTrue(page.fakes.all.isEmpty)
    }

    // MARK: helpers

    private final class Fakes {
        var all: [FakePlayback] = []
    }

    private final class AccountBox {
        var value: AppEnvironment.Account
        init(_ value: AppEnvironment.Account) { self.value = value }
    }

    private struct Page {
        let model: VideoPageModel
        let fakes: Fakes
        let http: FixtureHTTP
        let account: AccountBox
    }

    private func makePage(_ route: VideoRoute, resume: (Int64, Int64)? = nil, loggedIn: Bool = false,
                          sleep: @escaping (Double) async -> Void = { _ in _ = try? await Task.sleep(nanoseconds: 3_600_000_000_000) },
                          transport: FixtureHTTP = FixtureHTTP()) -> Page {
        let fakes = Fakes()
        let account = AccountBox(loggedIn ? .loggedIn(name: "测试", vip: false) : .loggedOut)
        let client = BiliClient(transport: transport, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
        let suite = "video-page-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let model = VideoPageModel(route: route, client: client, settings: settings, account: { account.value },
                                   makeController: { item in
                                       let fake = FakePlayback(item: item)
                                       fake.resume = resume.map { (timeMs: $0.0, cid: $0.1) }
                                       fakes.all.append(fake)
                                       return fake
                                   },
                                   sleep: sleep)
        return Page(model: model, fakes: fakes, http: transport, account: account)
    }

    private func waitUntil(_ seconds: Double = 5, _ condition: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("timed out", file: file, line: line)
    }
}

/// Serves the app's demo fixtures and records every request.
class FixtureHTTP: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [HTTPRequest] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { log.append(request) }
        let (status, body) = answer(request)
        return HTTPResponse(status: status, headers: [:], body: body, finalURL: request.url)
    }

    func answer(_ request: HTTPRequest) -> (Int, Data) {
        DemoFixtures.response(for: request.url, method: request.method)
    }

    func requests(to path: String) -> [HTTPRequest] {
        lock.withLock { log.filter { $0.url.path == path } }
    }
}

private final class RedirectingHTTP: FixtureHTTP {
    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard request.url.path == "/x/web-interface/wbi/view" else { return super.answer(request) }
        return DemoFixtures.ok(#"{"bvid":"BV1Redirect01","aid":1,"title":"番剧","pages":[{"cid":1,"page":1,"part":"","duration":100}],"redirect_url":"https://www.bilibili.com/bangumi/play/ep1"}"#)
    }
}

@MainActor
final class FakePlayback: PlaybackControlling {
    let item: PlayItem
    let player = AVPlayer()
    var phase: PlaybackController.Phase = .idle
    var mode: PlaybackController.Mode = .ripper
    var overlay = OverlayStats()
    var playing: PlayingStream?
    var qualities: [QualityOption] = []
    var selectedQuality = 80
    var playingQuality: Int?
    var codec: VideoCodec = .hevc
    var btrEnabled = true
    var resume: (timeMs: Int64, cid: Int64)?
    var position: Double = 0
    var duration: Double = 200
    var buffered: Double = 0
    var isPlaying = false
    var videoSize: CGSize?
    var rate: Float = 1
    var onEnd: (@MainActor () -> Void)?
    var onPosition: (@MainActor (Double) -> Void)?

    private(set) var starts: [(time: Double, autoplay: Bool)] = []
    private(set) var seeks: [Double] = []
    private(set) var stopped = false
    private(set) var paused = false

    init(item: PlayItem) {
        self.item = item
    }

    func tick(_ seconds: Double) {
        position = seconds
        onPosition?(seconds)
    }

    func start(at time: Double, autoplay: Bool) async {
        starts.append((time, autoplay))
        stopped = false
        position = time
        phase = .playing
        isPlaying = autoplay
    }

    func stop() {
        stopped = true
        isPlaying = false
        phase = .idle
    }

    func play() { isPlaying = true }

    func pause() {
        paused = true
        isPlaying = false
    }

    func seek(to seconds: Double) async {
        seeks.append(seconds)
        position = seconds
    }

    func setQuality(_ quality: Int) async { selectedQuality = quality }
    func setCodec(_ codec: VideoCodec) async { self.codec = codec }
    func setBTR(_ enabled: Bool) async { btrEnabled = enabled }
}
