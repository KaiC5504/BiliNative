import SwiftUI
import XCTest
@testable import BiliNative

/// The real home screen in a window, with demo data (logged in), and a video page pushed the two ways KaiC opens
/// one: straight from the 推荐 feed, the root of the stack, and from 历史记录. Build 5 on iOS 27 broke only the
/// first: the page never loaded its comments and kept its portrait layout after turning.
@MainActor
final class HomeFlowTests: XCTestCase {
    private typealias F = VideoPageFixtures
    private var window: UIWindow?
    private let http = FixtureHTTP()
    private var env: AppEnvironment!

    override func setUp() async throws {
        UserDefaults.standard.set(true, forKey: "DemoData")
        env = AppEnvironment(http: http)
    }

    override func tearDown() async throws {
        env.navigator.path = []
        try? await Task.sleep(for: .milliseconds(600))
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        UserDefaults.standard.removeObject(forKey: "DemoData")
        let orientation = OrientationController.shared
        orientation.locked = false
        orientation.exitToInline()
        if let scene = Self.scene {
            _ = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        }
    }

    func testPageOpenedFromTheFeed() async throws {
        let window = try await showHome()
        let fed = await waitUntil(5) { !self.http.requests(to: "/x/web-interface/wbi/index/top/feed/rcmd").isEmpty }
        XCTAssertTrue(fed, "the feed never loaded")
        // What a 推荐 card does.
        env.navigator.open(VideoRoute(bvid: F.bvidA))
        try await checkPage(in: window, depth: 2)
    }

    func testPageOpenedFromHistory() async throws {
        let window = try await showHome()
        env.navigator.open(.history)
        let listed = await waitUntil(5) { !self.http.requests(to: "/x/web-interface/history/cursor").isEmpty }
        XCTAssertTrue(listed, "历史记录 never loaded")
        _ = await waitUntil(3) { self.stackDepth(in: window) == 2 }
        env.navigator.open(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 20))
        try await checkPage(in: window, depth: 3)
    }

    // MARK: helpers

    private func checkPage(in window: UIWindow, depth: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let pushed = await waitUntil(5) { self.stackDepth(in: window) == depth }
        XCTAssertTrue(pushed, "the page was not pushed: \(stackDepth(in: window)) controllers", file: file, line: line)
        let playing = await waitUntil(10) { (OrientationController.shared.owner as? VideoPageModel)?.controller?.isPlaying == true }
        XCTAssertTrue(playing, "the page never played", file: file, line: line)
        let model = try XCTUnwrap(OrientationController.shared.owner as? VideoPageModel, file: file, line: line)
        let host = try XCTUnwrap(Self.find(PlayerHostView.self, in: window), "no player", file: file, line: line)
        try await expectInline(host, in: window, "on opening", file: file, line: line)

        // A swipe to 评论 shows the list, which loads.
        let pager = try XCTUnwrap(Self.pager(in: window), "no 简介/评论 pager", file: file, line: line)
        pager.setContentOffset(CGPoint(x: pager.bounds.width, y: 0), animated: false)
        let loaded = await waitUntil(8) { !self.http.requests(to: "/x/v2/reply/wbi/main").isEmpty }
        XCTAssertTrue(loaded, "评论 never asked for the comments", file: file, line: line)
        pager.setContentOffset(.zero, animated: false)

        let scene = try XCTUnwrap(Self.scene)
        OrientationController.shared.enterLandscape()
        let turned = await waitUntil(8) { scene.effectiveGeometry.interfaceOrientation.isLandscape && window.bounds.width > window.bounds.height }
        XCTAssertTrue(turned, "never turned", file: file, line: line)
        let filled = await waitUntil(5) { Self.close(self.frame(of: host, in: window), window.bounds) }
        XCTAssertTrue(filled, "landscape: the player is \(frame(of: host, in: window)) in \(window.bounds)", file: file, line: line)

        OrientationController.shared.exitToInline()
        let upright = await waitUntil(8) { scene.effectiveGeometry.interfaceOrientation == .portrait && window.bounds.width < window.bounds.height }
        XCTAssertTrue(upright, "never turned back", file: file, line: line)
        try await expectInline(host, in: window, "after landscape", file: file, line: line)

        OrientationController.shared.enterVertical()
        // 竖屏 sets a landscape video above the middle, the page's whole height given to the player.
        let tall = await waitUntil(5) {
            let frame = self.frame(of: host, in: window)
            return abs(frame.width - window.bounds.width) < 1 && abs(frame.height - window.bounds.height * VerticalLayout.videoCentre * 2) < 1
        }
        XCTAssertTrue(tall, "竖屏: the player is \(frame(of: host, in: window)) in \(window.bounds)", file: file, line: line)
        OrientationController.shared.exitToInline()
        try await expectInline(host, in: window, "after 竖屏", file: file, line: line)
        XCTAssertFalse(model.closed)
    }

    /// Under the status bar, the window's width, 16:9.
    private func expectInline(_ host: UIView, in window: UIWindow, _ when: String,
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        let width = window.bounds.width
        let placed = await waitUntil(5) {
            let frame = self.frame(of: host, in: window)
            return abs(frame.minX) < 1 && abs(frame.width - width) < 1 && abs(frame.height - width * 9 / 16) < 1
                && abs(frame.minY - window.safeAreaInsets.top) < 1
        }
        XCTAssertTrue(placed, "\(when): the player is \(frame(of: host, in: window)) in \(window.bounds), "
                      + "safe area \(window.safeAreaInsets)", file: file, line: line)
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    private func frame(of view: UIView, in window: UIWindow) -> CGRect {
        guard view.window === window else { return .null }
        return view.convert(view.bounds, to: window)
    }

    private func showHome() async throws -> UIWindow {
        let scene = try XCTUnwrap(Self.scene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: HomeView().environment(env))
        window.makeKeyAndVisible()
        self.window = window
        let laidOut = await waitUntil(5) { (window.rootViewController?.view.bounds.width ?? 0) > 0 }
        XCTAssertTrue(laidOut, "home never laid out")
        return window
    }

    private func stackDepth(in window: UIWindow) -> Int {
        Self.navigationController(in: window.rootViewController)?.viewControllers.count ?? 0
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

    private static func navigationController(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children {
            if let found = navigationController(in: child) { return found }
        }
        return nil
    }

    /// The top page's view of the given type.
    private static func find<View: UIView>(_ type: View.Type, in window: UIWindow) -> View? {
        guard let page = navigationController(in: window.rootViewController)?.topViewController?.view else { return nil }
        return first(in: page) { $0 is View } as? View
    }

    /// The paging scroll view under the top page's tab row.
    private static func pager(in window: UIWindow) -> UIScrollView? {
        guard let page = navigationController(in: window.rootViewController)?.topViewController?.view else { return nil }
        return first(in: page) { ($0 as? UIScrollView)?.isPagingEnabled == true } as? UIScrollView
    }

    private static func first(in view: UIView, where matches: (UIView) -> Bool) -> UIView? {
        if matches(view) { return view }
        for subview in view.subviews {
            if let found = first(in: subview, where: matches) { return found }
        }
        return nil
    }
}
