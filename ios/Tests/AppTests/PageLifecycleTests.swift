import Observation
import SwiftUI
import XCTest
import AppLogic
import BiliAPI
@testable import BiliNative

/// The app's own stack: a NavigationStack bound to `AppNavigator.path` with `videoPageDestinations()`, as HomeView.
private struct StackHarness: View {
    @Bindable var navigator: AppNavigator

    var body: some View {
        NavigationStack(path: $navigator.path) {
            Color.clear
                .videoPageDestinations()
        }
    }
}

/// Real video pages pushed and popped on a SwiftUI navigation stack, as related videos and history will push
/// them: the page underneath pauses and resumes, a popped page stops, and a page popped during picture in
/// picture is kept and comes back on top of the stack with the same host view. The simulator has no picture in
/// picture, so its state is set on the model by hand.
@MainActor
final class PageLifecycleTests: XCTestCase {
    private typealias F = VideoPageFixtures
    private var window: UIWindow?
    private let env = AppEnvironment()
    private var navigator: AppNavigator { env.navigator }

    override func tearDown() async throws {
        PiPKeeper.shared.release()
        navigator.path = []
        try? await Task.sleep(for: .milliseconds(600))
        window?.isHidden = true
        window = nil
        let orientation = OrientationController.shared
        orientation.locked = false
        orientation.videoIsVertical = false
        orientation.exitToInline()
    }

    func testPushCoversThePageBelowAndPopResumesIt() async throws {
        try await showStack()
        let below = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        let top = makePage(VideoRoute(bvid: F.bvidC, startSeconds: 0))

        navigator.show(below.model)
        let belowFake = try await playing(below)
        navigator.show(top.model)
        let topFake = try await playing(top)
        try await waitUntil { below.model.covered }
        XCTAssertFalse(belowFake.isPlaying)
        XCTAssertTrue(belowFake.paused)
        XCTAssertFalse(belowFake.stopped, "a covered page keeps its controller")
        XCTAssertTrue(belowFake.prefetchDropped)
        XCTAssertTrue(below.model.controller === belowFake)
        XCTAssertTrue(OrientationController.shared.owner === top.model, "the covered page's late end took the top page's orientation")

        navigator.path.removeLast()
        try await waitUntil { top.model.closed && belowFake.isPlaying }
        XCTAssertTrue(topFake.stopped)
        XCTAssertNil(top.model.controller)
        XCTAssertEqual(belowFake.starts.count, 1, "going back does not reload")
        XCTAssertTrue(OrientationController.shared.owner === below.model)

        navigator.path = []
        try await waitUntil { below.model.closed }
        XCTAssertTrue(belowFake.stopped)
        XCTAssertNil(OrientationController.shared.owner)
    }

    func testJumpingBackOverSeveralPagesClosesTheCoveredOnes() async throws {
        try await showStack()
        let below = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        let top = makePage(VideoRoute(bvid: F.bvidC, startSeconds: 0))
        navigator.show(below.model)
        let belowFake = try await playing(below)
        navigator.show(top.model)
        let topFake = try await playing(top)
        try await waitUntil { below.model.covered }

        navigator.path = []
        try await waitUntil { below.model.closed && top.model.closed }
        XCTAssertTrue(belowFake.stopped)
        XCTAssertTrue(topFake.stopped)
    }

    func testPartSwitchKeepsTheSamePlayer() async throws {
        try await showStack()
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        navigator.show(page.model)
        let first = try await playing(page)
        let host = try XCTUnwrap(page.model.host)
        XCTAssertTrue(first.player === page.model.player)
        XCTAssertTrue(host.playerLayer.player === page.model.player)

        await page.model.handleEnd()
        XCTAssertEqual(page.model.current, PlayItem(bvid: F.bvidA, cid: F.cidA2))
        let second = try XCTUnwrap(page.fakes.all.last)
        XCTAssertFalse(second === first)
        XCTAssertTrue(second.player === page.model.player, "the next part got a player of its own")
        XCTAssertTrue(page.model.host === host)
        XCTAssertTrue(host.playerLayer.player === page.model.player, "the layer lost the page's player")
        XCTAssertNotNil(host.window)
    }

    func testPageLeftDuringPiPIsKeptAndRestoredWithItsHostView() async throws {
        try await showStack()
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        navigator.show(page.model)
        let fake = try await playing(page)
        let host = try XCTUnwrap(page.model.host)
        page.model.pipChanged(true)

        navigator.path = []
        try await waitUntil { PiPKeeper.shared.kept === page.model && host.window == nil }
        XCTAssertFalse(fake.stopped)
        XCTAssertTrue(fake.isPlaying, "the small window goes on playing after the page closed")

        var restored: Bool?
        host.restoreForPiPStop { restored = $0 }
        try await waitUntil { restored != nil && PiPKeeper.shared.kept == nil }
        XCTAssertEqual(restored, true)
        XCTAssertEqual(navigator.path.count, 1)
        XCTAssertNotNil(host.window, "the restored page shows the host view picture in picture left from")
        XCTAssertTrue(page.model.host === host)
        XCTAssertTrue(host.playerLayer.player === page.model.player)
        XCTAssertEqual(page.fakes.all.count, 1, "restoring reloaded the video")
        XCTAssertEqual(fake.starts.count, 1)

        page.model.pipChanged(false)
        XCTAssertFalse(fake.stopped, "the restored page plays on inline")
        XCTAssertTrue(fake.isPlaying)
    }

    /// Going back from a page in the small window: whichever of the two pages reports first, the page below
    /// stays paused and the popped one is kept.
    func testGoingBackFromAPageInPiPLeavesThePageBelowPaused() async throws {
        try await showStack()
        let below = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        let top = makePage(VideoRoute(bvid: F.bvidC, startSeconds: 0))
        navigator.show(below.model)
        let belowFake = try await playing(below)
        navigator.show(top.model)
        let topFake = try await playing(top)
        try await waitUntil { below.model.covered }
        top.model.pipChanged(true)

        navigator.path.removeLast()
        try await waitUntil { PiPKeeper.shared.kept === top.model && !below.model.covered }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(belowFake.isPlaying, "two videos play at once")
        XCTAssertTrue(topFake.isPlaying)
        XCTAssertTrue(PiPKeeper.shared.kept === top.model)
    }

    /// The restore button while another page is on the stack: the kept page comes back on top of it.
    func testRestoreWithAPageOnTheStackPushesOnTop() async throws {
        try await showStack()
        let below = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        let top = makePage(VideoRoute(bvid: F.bvidC, startSeconds: 0))
        navigator.show(below.model)
        let belowFake = try await playing(below)
        navigator.show(top.model)
        let topFake = try await playing(top)
        let host = try XCTUnwrap(top.model.host)
        try await waitUntil { below.model.covered }
        top.model.pipChanged(true)
        navigator.path.removeLast()
        try await waitUntil { PiPKeeper.shared.kept === top.model && host.window == nil && !below.model.covered }

        var restored: Bool?
        host.restoreForPiPStop { restored = $0 }
        try await waitUntil { restored != nil && PiPKeeper.shared.kept == nil && below.model.covered }
        XCTAssertEqual(restored, true)
        XCTAssertEqual(navigator.path.count, 2, "the restored page replaced the one below instead of going on top")
        XCTAssertNotNil(host.window)
        XCTAssertFalse(topFake.stopped)
        XCTAssertEqual(top.fakes.all.count, 1, "restoring reloaded the video")
        XCTAssertFalse(belowFake.stopped)
        XCTAssertFalse(belowFake.isPlaying)

        // The window finishes closing once it is back in the page.
        top.model.pipChanged(false)
        navigator.path.removeLast()
        try await waitUntil { top.model.closed && !below.model.covered }
        XCTAssertTrue(topFake.stopped)
        XCTAssertFalse(below.model.closed)
    }

    func testClosingTheSmallWindowOfAKeptPageStopsIt() async throws {
        try await showStack()
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        navigator.show(page.model)
        let fake = try await playing(page)
        page.model.pipChanged(true)
        navigator.path = []
        try await waitUntil { PiPKeeper.shared.kept === page.model }

        page.model.pipChanged(false)
        XCTAssertNil(PiPKeeper.shared.kept)
        XCTAssertTrue(fake.stopped)
        XCTAssertTrue(page.model.closed)
    }

    // MARK: helpers

    private final class Fakes {
        var all: [FakePlayback] = []
    }

    private struct Page {
        let model: VideoPageModel
        let fakes: Fakes
    }

    private func makePage(_ route: VideoRoute) -> Page {
        let fakes = Fakes()
        let client = BiliClient(transport: FixtureHTTP(), cookies: CookieJar(["buvid3": "b3", "buvid4": "b4"]))
        let suite = "page-lifecycle-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let model = VideoPageModel(route: route, client: client, settings: settings, account: { .loggedOut },
                                   makeController: { item, player in
                                       let fake = FakePlayback(item: item, player: player)
                                       fakes.all.append(fake)
                                       return fake
                                   })
        return Page(model: model, fakes: fakes)
    }

    private func playing(_ page: Page) async throws -> FakePlayback {
        try await waitUntil { page.fakes.all.first?.isPlaying == true }
        return try XCTUnwrap(page.fakes.all.first)
    }

    private func showStack() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: StackHarness(navigator: navigator).environment(env))
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil { (window.rootViewController?.view.bounds.width ?? 0) > 0 }
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
