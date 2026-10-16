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
                .navigationDestination(for: Int.self) { _ in
                    VideoPageView(route: VideoRoute(bvid: VideoPageFixtures.bvidA), prompts: prompts)
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
        try await waitUntil(10) { page == nil && actions == nil && comments == nil }
        XCTAssertNil(page, "the popped page's VideoPageModel is still alive")
        XCTAssertNil(actions, "the popped page's ActionsModel is still alive")
        XCTAssertNil(comments, "the popped page's CommentsModel is still alive")
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
