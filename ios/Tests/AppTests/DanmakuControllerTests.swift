import AVFoundation
import UIKit
import XCTest
import BiliAPI
import Danmaku
@testable import BiliNative

@MainActor
final class DanmakuControllerTests: XCTestCase {
    private static let segmentPath = "/x/v2/dm/web/seg.so"

    func testLoadsTheFirstSegmentAtStartAndTheNextNearTheBoundary() async {
        let page = make()
        page.controller.update(positionMs: 0, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1])

        for ms in stride(from: Int64(16), through: 320, by: 16) {
            page.controller.update(positionMs: ms, playing: true)
        }
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1], "a loaded segment is never asked for again")

        page.controller.update(positionMs: 335_000, playing: true)
        page.controller.update(positionMs: 335_016, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1, 2])

        page.controller.update(positionMs: 361_000, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1, 2])
    }

    func testSeekFarAheadLoadsThatSegmentOnly() async {
        let page = make()
        page.controller.seeked(toMs: 800_000)
        page.controller.update(positionMs: 800_000, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [3])
        XCTAssertFalse(page.controller.pendingItems(atMs: 800_000).isEmpty, "what is on screen at 800 s is laid out at once")
    }

    func testClosedSegmentStopsDanmaku() async {
        let page = make(SegmentHTTP { index, _ in (200, DanmakuFixtures.segment(index: index, closed: true)) })
        page.controller.update(positionMs: 0, playing: true)
        await page.controller.settle()
        XCTAssertTrue(page.controller.closed)
        XCTAssertTrue(page.controller.pendingItems(atMs: 5_000).isEmpty)
        page.controller.update(positionMs: 340_000, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1])
    }

    func testFailedSegmentRetriesOnTheNextSeek() async {
        let page = make(SegmentHTTP { index, attempt in attempt == 1 ? (500, Data()) : (200, DanmakuFixtures.segment(index: index)) })
        page.controller.update(positionMs: 0, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1])

        page.controller.update(positionMs: 16, playing: true)
        page.controller.update(positionMs: 32, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1], "a failed segment waits for the next boundary or seek")
        XCTAssertTrue(page.controller.pendingItems(atMs: 32).isEmpty)

        page.controller.seeked(toMs: 5_000)
        page.controller.update(positionMs: 5_000, playing: true)
        await page.controller.settle()
        XCTAssertEqual(indices(page.http), [1, 1])
        XCTAssertFalse(page.controller.pendingItems(atMs: 5_000).isEmpty)
    }

    func testOwnDanmakuAppearsAtOnce() {
        let page = make()
        _ = page.controller.pendingItems(atMs: 12_000)
        page.controller.showOwn(DanmakuDraft(cid: VideoPageFixtures.cidA1, bvid: VideoPageFixtures.bvidA, text: "我来了", mode: 1,
                                             fontSize: 25, color: 0xFFFFFF, gradient: false, progressMs: 12_000))
        let now = page.controller.pendingItems(atMs: 12_016)
        XCTAssertEqual(now.filter(\.isOwn).map(\.text), ["我来了"])
        XCTAssertTrue(page.controller.pendingItems(atMs: 12_032).isEmpty, "shown once")
    }

    func testBlockRulesRefilterWhatIsLoaded() async {
        let page = make()
        page.controller.update(positionMs: 0, playing: true)
        await page.controller.settle()
        let before = page.controller.generation
        page.controller.rules = [BlockRule(id: 1, kind: .keyword, filter: "弹幕")]
        XCTAssertNotEqual(page.controller.generation, before, "the view clears the screen")
        let items = page.controller.pendingItems(atMs: 30_000)
        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items.contains { !$0.isOwn && $0.text.contains("弹幕") })
        XCTAssertTrue(items.contains { $0.isOwn }, "one's own danmaku are never blocked")
    }

    func testSmallStepBackDoesNotReplay() async {
        let page = make()
        page.controller.update(positionMs: 0, playing: true)
        await page.controller.settle()
        // The fixture has a scrolling danmaku at 10 100 ms.
        _ = page.controller.pendingItems(atMs: 10_200)
        XCTAssertTrue(page.controller.pendingItems(atMs: 10_050).isEmpty)
        XCTAssertTrue(page.controller.pendingItems(atMs: 10_200).isEmpty, "the one at 10 100 ms is not replayed")
    }

    // MARK: renderer

    func testScrollingDanmakuNeverOverlapAndStayInTheArea() async {
        let page = make()
        page.controller.update(positionMs: 0, playing: true)
        await page.controller.settle()
        let view = DanmakuView(controller: page.controller, settings: page.settings, player: { nil }, fullScreen: { true })
        view.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        var most = 0
        for frame in 0..<(60 * 12) {
            view.show(at: Double(frame) / 60, playing: true, options: page.settings.danmaku)
            let shown = view.visibleFrames
            most = max(most, shown.count)
            if let clash = overlap(shown) {
                XCTFail("overlap at \(Double(frame) / 60) s: \(clash)")
                return
            }
            for item in shown where item.kind != .bottom {
                XCTAssertLessThanOrEqual(item.frame.maxY, 402 * page.settings.danmaku.area + 1)
            }
        }
        XCTAssertGreaterThan(most, 12, "the demo segment should fill the lanes")
    }

    func testSeekClearsAndLaysOutMidFlight() async {
        let page = make()
        page.controller.update(positionMs: 0, playing: true)
        await page.controller.settle()
        let view = DanmakuView(controller: page.controller, settings: page.settings, player: { nil }, fullScreen: { false })
        view.frame = CGRect(x: 0, y: 0, width: 402, height: 226)
        view.show(at: 3, playing: true, options: page.settings.danmaku)
        view.show(at: 60, playing: true, options: page.settings.danmaku)
        let shown = view.visibleFrames
        XCTAssertFalse(shown.isEmpty, "a seek lays out what would be on screen")
        XCTAssertTrue(shown.contains { $0.kind == .scroll && $0.frame.maxX < 402 }, "scrolling ones are placed mid-flight")
        XCTAssertNil(overlap(shown))

        view.show(at: 60.1, playing: true, options: page.settings.danmaku)
        let paused = view.visibleFrames.map(\.frame)
        view.show(at: 60.1, playing: false, options: page.settings.danmaku)
        XCTAssertEqual(view.visibleFrames.map(\.frame), paused, "nothing moves while the video time stands still")
    }

    func testSettingsPersistAsJSON() {
        let suite = "danmaku-settings-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.danmaku, .defaults)
        XCTAssertEqual(settings.danmaku.scrollDuration, 7)
        settings.danmaku.enabled = false
        settings.danmaku.area = 0.25
        settings.danmaku.speed = 4
        settings.danmaku.filter.dedupe = true
        XCTAssertNotNil(defaults.data(forKey: "danmaku.settings"))
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.danmaku, settings.danmaku)
        XCTAssertEqual(reloaded.danmaku.scrollDuration, 4)
    }

    // MARK: helpers

    private struct Page {
        let controller: DanmakuController
        let settings: AppSettings
        let http: FixtureHTTP
    }

    private func make(_ http: FixtureHTTP = FixtureHTTP()) -> Page {
        let client = BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
        let suite = "danmaku-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let controller = DanmakuController(client: client, settings: settings, ownHash: { MidHash.of(uid: DanmakuFixtures.demoMid) })
        controller.load(cid: VideoPageFixtures.cidA1, bvid: VideoPageFixtures.bvidA, durationMs: 900_000)
        return Page(controller: controller, settings: settings, http: http)
    }

    private func indices(_ http: FixtureHTTP) -> [Int] {
        http.requests(to: Self.segmentPath).compactMap { request in
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "segment_index" }?.value.flatMap { Int($0) }
        }
    }

    /// Two danmaku of the same kind drawn over each other. Top and bottom ones may cross scrolling ones,
    /// as in the official app.
    private func overlap(_ shown: [(kind: LaneLayout.Kind, frame: CGRect)]) -> String? {
        for (i, a) in shown.enumerated() {
            for b in shown[(i + 1)...] where a.kind == b.kind {
                if a.frame.insetBy(dx: 0.5, dy: 0.5).intersects(b.frame.insetBy(dx: 0.5, dy: 0.5)) {
                    return "\(a.kind) \(a.frame) and \(b.frame)"
                }
            }
        }
        return nil
    }
}

/// Answers seg.so through `answer(index, attempt)`, counting attempts from 1; everything else from the fixtures.
private final class SegmentHTTP: FixtureHTTP {
    private let lock = NSLock()
    private var attempts = 0
    private let answerSegment: (Int, Int) -> (Int, Data)

    init(_ answer: @escaping (Int, Int) -> (Int, Data)) {
        answerSegment = answer
        super.init()
    }

    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        guard request.url.path == "/x/v2/dm/web/seg.so" else { return super.answer(request) }
        let attempt = lock.withLock {
            attempts += 1
            return attempts
        }
        let index = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "segment_index" }?.value.flatMap { Int($0) } ?? 1
        return answerSegment(index, attempt)
    }
}
