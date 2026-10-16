import Observation
import SwiftUI
import XCTest
import BiliAPI
@testable import BiliNative

@Observable
@MainActor
final class PanelDriver {
    var panel: PlayerPanel?
}

private struct PageHarness: View {
    @Bindable var driver: PanelDriver

    var body: some View {
        NavigationStack {
            VideoPageView(route: VideoRoute(bvid: VideoPageFixtures.bvidA), panel: $driver.panel)
        }
    }
}

/// Hosts the real video page in a window, opens each panel and dismisses it the way a tap outside would.
/// A test cannot inject touches into SwiftUI, so it hit tests the point to prove the dismiss layer is what a tap there
/// reaches, and fires that layer's action.
@MainActor
final class PanelPresentationTests: XCTestCase {
    private var window: UIWindow?
    private let driver = PanelDriver()

    override func setUp() async throws {
        UserDefaults.standard.set(true, forKey: "DemoData")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "DemoData")
        // Tears the page down: a page left alive would keep the orientation owner and react to later tests.
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        let orientation = OrientationController.shared
        orientation.locked = false
        orientation.exitToInline()
        if let scene = Self.scene {
            _ = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        }
    }

    func testEachPanelOpensAndClosesInLandscape() async throws {
        let scene = try XCTUnwrap(Self.scene)
        OrientationController.shared.enterLandscape()
        let turned = await waitUntil(8) { scene.effectiveGeometry.interfaceOrientation.isLandscape }
        XCTAssertTrue(turned, "the scene never turned to landscape")
        try await exercisePanels(landscape: true)
    }

    func testEachPanelOpensAndClosesInPortrait() async throws {
        try await exercisePanels(landscape: false)
    }

    private func exercisePanels(landscape: Bool) async throws {
        let window = try await showPage()
        XCTAssertEqual(window.bounds.width > window.bounds.height, landscape)
        for panel in PlayerPanel.allCases {
            driver.panel = panel
            let opened = await waitUntil(3) { Self.find(panel.identifier, in: window) != nil }
            XCTAssertTrue(opened, "\(panel) did not open")
            try await Task.sleep(for: .milliseconds(600))

            let probe = try XCTUnwrap(Self.find(panel.identifier, in: window), "\(panel) is not on screen")
            let catchers = Self.findAll(TapCatcherView.identifier, in: window)
            XCTAssertEqual(catchers.count, 1, "\(panel) should have one dismiss layer: \(catchers.map(Self.describe))")
            let frame = probe.convert(probe.bounds, to: window)
            let size = window.bounds.size

            let outside = landscape ? CGPoint(x: size.width * 0.12, y: size.height / 2) : CGPoint(x: size.width / 2, y: size.height * 0.12)
            XCTAssertFalse(frame.contains(outside), "\(panel) covers the point meant to be outside it: \(frame)")
            let hit = window.hitTest(outside, with: nil)
            guard let catcher = hit as? TapCatcherView else {
                XCTFail("a tap outside \(panel) reaches \(Self.describe(hit)); dismiss layers: \(catchers.map(Self.describe))")
                driver.panel = nil
                _ = await waitUntil(3) { Self.find(panel.identifier, in: window) == nil }
                continue
            }

            let inside = CGPoint(x: frame.midX, y: frame.midY)
            let insideHit = window.hitTest(inside, with: nil)
            XCTAssertFalse(insideHit is TapCatcherView, "a tap inside \(panel) would dismiss it: \(Self.describe(insideHit))")

            _ = catcher.accessibilityActivate()
            let gone = await waitUntil(3) { Self.find(panel.identifier, in: window) == nil }
            XCTAssertTrue(gone, "\(panel) did not close")
            XCTAssertNil(driver.panel)
        }
        let clean = await waitUntil(3) { Self.findAll(TapCatcherView.identifier, in: window).isEmpty }
        XCTAssertTrue(clean, "dismiss layers left behind: \(Self.findAll(TapCatcherView.identifier, in: window).map(Self.describe))")
    }

    private func showPage() async throws -> UIWindow {
        let scene = try XCTUnwrap(Self.scene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: PageHarness(driver: driver).environment(AppEnvironment()))
        window.makeKeyAndVisible()
        self.window = window
        let laidOut = await waitUntil(5) { (window.rootViewController?.view.bounds.width ?? 0) > 0 }
        XCTAssertTrue(laidOut, "the page never laid out")
        return window
    }

    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private static func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for subview in view.subviews {
            if let found = find(identifier, in: subview) { return found }
        }
        return nil
    }

    private static func findAll(_ identifier: String, in view: UIView) -> [UIView] {
        (view.accessibilityIdentifier == identifier ? [view] : []) + view.subviews.flatMap { findAll(identifier, in: $0) }
    }

    /// The view and its superviews up to the window, for a failure message.
    private static func describe(_ view: UIView?) -> String {
        var parts: [String] = []
        var current = view
        while let view = current {
            parts.append("\(type(of: view)) \(view.frame.integral) alpha \(view.alpha) hidden \(view.isHidden)")
            current = view.superview
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: " <- ")
    }
}

@MainActor
final class PanelActionTests: XCTestCase {
    private typealias F = VideoPageFixtures
    private let watchLaterPath = "/x/v2/history/toview/add"

    func testWatchLaterAsksForLoginWithoutSendingAnything() async {
        let http = FixtureHTTP()
        let model = makeModel(route: VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0), http: http, loggedIn: false)
        await model.load()
        let result = await model.addToWatchLater()
        XCTAssertEqual(result, .needsLogin)
        XCTAssertTrue(http.requests(to: watchLaterPath).isEmpty)
    }

    func testWatchLaterSendsTheCurrentVideosAid() async throws {
        let http = WatchLaterHTTP()
        let model = makeModel(route: VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0), http: http, loggedIn: true)
        await model.load()
        let result = await model.addToWatchLater()
        XCTAssertEqual(result, .added)
        let sent = try XCTUnwrap(http.requests(to: watchLaterPath).first)
        let body = String(decoding: sent.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("aid=\(F.aidA)"), body)
        XCTAssertTrue(body.contains("csrf=T"), body)
    }

    func testSleepChoiceFollowsTheTimer() async {
        XCTAssertEqual(MorePanel.sleepChoice(for: nil), .off)
        XCTAssertEqual(MorePanel.sleepChoice(for: 15), .minutes15)
        XCTAssertEqual(MorePanel.sleepChoice(for: 30), .minutes30)
        XCTAssertEqual(MorePanel.sleepChoice(for: 60), .minutes60)
        XCTAssertEqual(MorePanel.sleepChoice(for: 45), .custom)

        let model = makeModel(route: VideoRoute(bvid: F.bvidA), http: FixtureHTTP(), loggedIn: false)
        model.setSleepTimer(minutes: 45)
        XCTAssertEqual(model.sleepMinutes, 45)
        model.setSleepTimer(minutes: nil)
        XCTAssertNil(model.sleepMinutes)
        XCTAssertNil(model.sleepDeadline)
    }

    func testEpisodesListThePartsOrElseTheCurrentSection() async throws {
        let parted = makeModel(route: VideoRoute(bvid: F.bvidA), http: FixtureHTTP(), loggedIn: false)
        await parted.load()
        let parts = EpisodesPanel.rows(detail: try XCTUnwrap(parted.detail), current: parted.current)
        XCTAssertEqual(parts.map(\.title), ["P1 上篇", "P2 下篇"])
        XCTAssertEqual(parts.map(\.duration), ["03:20", "03:00"])
        XCTAssertEqual(parts.map(\.selected), [false, true], "the part Bilibili last saw is the playing one")
        XCTAssertTrue(parts.allSatisfy(\.isPart))

        let single = makeModel(route: VideoRoute(bvid: F.bvidC, startSeconds: 0), http: FixtureHTTP(), loggedIn: false)
        await single.load()
        let episodes = EpisodesPanel.rows(detail: try XCTUnwrap(single.detail), current: single.current)
        XCTAssertEqual(episodes.map(\.title), ["第三集：归来"], "only the section holding the playing episode")
        XCTAssertEqual(episodes.map(\.selected), [true])
        XCTAssertFalse(episodes.contains { $0.isPart })
    }

    func testQualityAndSpeedLabels() {
        XCTAssertEqual(QualityPanel.title(for: QualityOption(id: 120, name: "超清 4K")), "4K 超高清")
        XCTAssertEqual(QualityPanel.title(for: QualityOption(id: 80, name: "高清 1080P")), "1080P 高清")
        XCTAssertEqual(QualityPanel.title(for: QualityOption(id: 32, name: "清晰 480P")), "480P 标清")
        XCTAssertEqual(QualityPanel.title(for: QualityOption(id: 999, name: "未知")), "未知")
        XCTAssertEqual(SpeedPanel.choices.map(\.label), ["3.0X", "2.0X", "1.5X", "1.25X", "1.0X", "0.75X", "0.5X"])
    }

    private func makeModel(route: VideoRoute, http: FixtureHTTP, loggedIn: Bool) -> VideoPageModel {
        var cookies = ["buvid3": "b3", "buvid4": "b4"]
        if loggedIn { cookies.merge(["SESSDATA": "s", "bili_jct": "T"]) { $1 } }
        let client = BiliClient(transport: http, cookies: CookieJar(cookies))
        let suite = "panel-actions-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        return VideoPageModel(route: route, client: client, settings: settings,
                              account: { loggedIn ? .loggedIn(name: "测试", vip: false) : .loggedOut },
                              makeController: { FakePlayback(item: $0, player: $1) })
    }
}

private final class WatchLaterHTTP: FixtureHTTP, @unchecked Sendable {
    override func answer(_ request: HTTPRequest) -> (Int, Data) {
        request.url.path == "/x/v2/history/toview/add" ? DemoFixtures.ok("null") : super.answer(request)
    }
}
