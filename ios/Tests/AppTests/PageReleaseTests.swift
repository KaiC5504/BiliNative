import Observation
import SwiftUI
import XCTest
@testable import BiliNative

@MainActor
@Observable
private final class ReleasePath {
    var pages: [Int] = []
}

private struct ReleaseHarness: View {
    @Bindable var path: ReleasePath
    let prompts: ActionPrompts

    var body: some View {
        NavigationStack(path: $path.pages) {
            Color.clear
                .navigationDestination(for: Int.self) { page in
                    if page == 1 {
                        VideoPageView(route: VideoRoute(bvid: VideoPageFixtures.bvidA), prompts: prompts)
                    } else {
                        Color.white
                    }
                }
        }
    }
}

/// A popped video page must free its models. Closures the models keep (asking for login, showing a toast) once
/// captured the page view, whose state holds the models: every page visited stayed alive with its player.
@MainActor
final class PageReleaseTests: XCTestCase {
    private var window: UIWindow?

    override func setUp() async throws {
        UserDefaults.standard.set(true, forKey: "DemoData")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "DemoData")
        window?.isHidden = true
        window = nil
    }

    func testPoppedPageFreesItsModels() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let path = ReleasePath()
        let prompts = ActionPrompts()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ReleaseHarness(path: path, prompts: prompts)
            .environment(AppEnvironment(http: FixtureHTTP())))
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil { (window.rootViewController?.view.bounds.width ?? 0) > 0 }

        path.pages = [1]
        try await waitUntil { prompts.actions != nil && prompts.comments != nil && OrientationController.shared.owner is VideoPageModel }
        weak var page = OrientationController.shared.owner as? VideoPageModel
        weak var actions = prompts.actions
        weak var comments = prompts.comments
        XCTAssertNotNil(page)

        path.pages = []
        try await waitUntil { page?.closed ?? true }
        // The test's own handle on the actions.
        prompts.actions = nil
        // SwiftUI may hold the last popped destination until the stack moves again; a plain page pushed and popped
        // lets it go, while a real cycle survives it.
        try await Task.sleep(for: .milliseconds(800))
        path.pages = [2]
        try await Task.sleep(for: .milliseconds(800))
        path.pages = []
        try await waitUntil(10) { page == nil && actions == nil && comments == nil }
        let leftover = Self.hostView(in: window).map { "a player view is still in the window (\($0.window != nil))" } ?? "no player view in the window"
        XCTAssertNil(page, "the popped page's VideoPageModel is still alive; \(leftover); host in a window: \(page?.host?.window != nil)")
        XCTAssertNil(actions, "the popped page's ActionsModel is still alive")
        XCTAssertNil(comments, "the popped page's CommentsModel is still alive")
    }

    func testDiagBisect() async throws {
        let parts: [Set<String>] = [[], ["link"], ["realdanmaku"], ["danmaku"]]
        var lines: [String] = []
        for omit in parts {
            LeakProbe.omit = omit
            let result = try await hostAndDrop()
            lines.append("omit \(omit.sorted()): \(result)")
            print("LEAKPROBE omit \(omit.sorted()): \(result)")
        }
        LeakProbe.omit = []
        XCTFail("DIAG " + lines.joined(separator: " | "))
    }

    private func hostAndDrop() async throws -> String {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prompts = ActionPrompts()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: VideoPageView(route: VideoRoute(bvid: VideoPageFixtures.bvidA), prompts: prompts)
            .environment(AppEnvironment(http: FixtureHTTP())))
        window.makeKeyAndVisible()
        self.window = window
        let made = await wait(8) { prompts.actions != nil && prompts.comments != nil && OrientationController.shared.owner is VideoPageModel }
        guard made else { return "never made" }
        weak var page = OrientationController.shared.owner as? VideoPageModel
        weak var actions = prompts.actions
        weak var comments = prompts.comments
        try await Task.sleep(for: .milliseconds(800))
        weak var host = page?.host
        weak var danmaku = page?.host?.danmakuContainer.subviews.first
        weak var hosting = window.rootViewController
        weak var container = Self.find(SurfaceContainer.self, in: window)
        weak var player = page?.player
        weak var controller = page?.controller as AnyObject?
        window.rootViewController = UIViewController()
        window.isHidden = true
        self.window = nil
        _ = await wait(5) { page?.closed ?? true }
        prompts.actions = nil
        _ = await wait(5) { page == nil && actions == nil && comments == nil }
        func state() -> String {
            "page \(page != nil), actions \(actions != nil), comments \(comments != nil), host \(host != nil), "
                + "danmaku \(danmaku != nil), hosting \(hosting != nil), container \(container != nil), "
                + "player \(player != nil), controller \(controller != nil)"
        }
        var result = state()
        if page != nil || actions != nil || comments != nil {
            PiPKeeper.shared.release()
            _ = await wait(2) { page == nil }
            result += "; after keeper release: " + state()
            player?.replaceCurrentItem(with: nil)
            _ = await wait(2) { page == nil }
            result += "; after emptying the player: " + state()
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            _ = await wait(2) { page == nil }
            result += "; after a memory warning: " + state()
        }
        return result
    }

    private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let found = view as? T { return found }
        for subview in view.subviews {
            if let found = find(type, in: subview) { return found }
        }
        return nil
    }

    private func wait(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private static func hostView(in view: UIView) -> PlayerHostView? {
        if let host = view as? PlayerHostView { return host }
        for subview in view.subviews {
            if let host = hostView(in: subview) { return host }
        }
        return nil
    }

    private func waitUntil(_ seconds: Double = 8, _ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        if !condition() { XCTFail("timed out", file: file, line: line) }
    }
}
