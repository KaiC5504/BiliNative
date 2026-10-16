import SwiftUI
import XCTest
import BiliAPI
@testable import BiliNative

private struct PromptsHarness: View {
    let prompts: ActionPrompts

    var body: some View {
        NavigationStack {
            VideoPageView(route: VideoRoute(bvid: VideoPageFixtures.bvidA), prompts: prompts)
        }
    }
}

/// Hosts the real video page in a window with demo data and puts up what 投币, 收藏, 已关注 and 分享 open, upright and
/// turned. The coin dialog and the favourites sheet are overlays in the page; the unfollow alert and the share sheet
/// are the system controllers here, so they are presented over the rotated page.
@MainActor
final class ActionPresentationTests: XCTestCase {
    private var window: UIWindow?
    private let prompts = ActionPrompts()
    private let http = FixtureHTTP()

    override func setUp() async throws {
        UserDefaults.standard.set(true, forKey: "DemoData")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "DemoData")
        window?.isHidden = true
        window = nil
        let orientation = OrientationController.shared
        orientation.locked = false
        orientation.exitToInline()
        if let scene = Self.scene {
            _ = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        }
    }

    func testCoinDialogOpensAndClosesInPortraitAndLandscape() async throws {
        let window = try await showPage()
        let actions = try await pageActions()
        try await openAndCloseCoinDialog(actions, in: window, landscape: false)

        try await turnToLandscape()
        try await openAndCloseCoinDialog(actions, in: window, landscape: true)
    }

    func testFavouriteSheetOpensAndAppliesTheDifference() async throws {
        let window = try await showPage()
        let actions = try await pageActions()
        actions.ask(.favourites)
        let opened = await waitUntil(3) { Self.find(FavouriteSheet.identifier, in: window) != nil }
        XCTAssertTrue(opened, "the favourites sheet did not open")
        XCTAssertEqual(prompts.overlay, .favourites)
        let model = try XCTUnwrap(prompts.favourites)
        let loaded = await waitUntil(5) { model.phase == .loaded }
        XCTAssertTrue(loaded, "the folders never loaded")
        XCTAssertEqual(model.ticked, [3001], "the default folder holds the video")

        model.toggle(3002)
        model.toggle(3001)
        XCTAssertEqual(model.change.add, [3002])
        XCTAssertEqual(model.change.remove, [3001])
        await model.apply(to: actions)
        let sent = try XCTUnwrap(http.requests(to: "/x/v3/fav/resource/batch-deal").last, "完成 sent nothing")
        let body = String(decoding: sent.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("add_media_ids=3002"), body)
        XCTAssertTrue(body.contains("del_media_ids=3001"), body)
        XCTAssertTrue(actions.favorited, "the video is still in a folder")

        try await Task.sleep(for: .milliseconds(400))
        let size = window.bounds.size
        let outside = CGPoint(x: size.width / 2, y: size.height * 0.15)
        let catcher = try XCTUnwrap(window.hitTest(outside, with: nil) as? TapCatcherView, "a tap above the sheet does not reach its dismiss layer")
        let probe = try XCTUnwrap(Self.find(FavouriteSheet.identifier, in: window))
        let frame = probe.convert(probe.bounds, to: window)
        XCTAssertFalse(window.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil) is TapCatcherView,
                       "a tap inside the sheet would close it")
        _ = catcher.accessibilityActivate()
        let gone = await waitUntil(3) { Self.find(FavouriteSheet.identifier, in: window) == nil }
        XCTAssertTrue(gone, "the favourites sheet did not close")
        XCTAssertNil(prompts.overlay)
    }

    func testUnfollowAlertInLandscape() async throws {
        let window = try await showPage()
        let actions = try await pageActions()
        try await turnToLandscape()

        actions.prompt = .unfollow
        let shown = await waitUntil(5) { Self.topPresented(in: window) is UIAlertController }
        XCTAssertTrue(shown, "the unfollow confirm never came up")
        let alert = try XCTUnwrap(Self.topPresented(in: window) as? UIAlertController)
        XCTAssertEqual(alert.title, "确定不再关注？")
        XCTAssertEqual(Set(alert.actions.compactMap(\.title)), ["取消", "确定"])
        XCTAssertEqual(OrientationController.shared.presentation, .landscape)

        prompts.unfollowAsked = false
        let gone = await waitUntil(5) { window.rootViewController?.presentedViewController == nil }
        XCTAssertTrue(gone, "the unfollow confirm did not go away")
        try assertStillLandscape(in: window)
    }

    func testShareSheetPresentsOverTheRotatedPlayer() async throws {
        let window = try await showPage()
        let actions = try await pageActions()
        try await turnToLandscape()

        actions.ask(.share)
        let shown = await waitUntil(5) { Self.topPresented(in: window) is UIActivityViewController }
        XCTAssertTrue(shown, "the share sheet never came up from the key window's top controller")
        XCTAssertEqual(OrientationController.shared.presentation, .landscape)

        window.rootViewController?.dismiss(animated: false)
        let gone = await waitUntil(5) { window.rootViewController?.presentedViewController == nil }
        XCTAssertTrue(gone, "the share sheet did not go away")
        try assertStillLandscape(in: window)
    }

    /// A login asked for in full screen: the page turns upright first, and the sheet goes up only once it has.
    func testLoginSheetFromLandscapeComesUpOverTheInlinePage() async throws {
        let window = try await showPage()
        _ = try await pageActions()
        let ready = await waitUntil(8) { prompts.comments != nil }
        XCTAssertTrue(ready, "the page never made its comments")
        try await turnToLandscape()
        let scene = try XCTUnwrap(Self.scene)

        prompts.comments?.fail(BiliError.api(code: -101, message: "账号未登录"))
        let shown = await waitUntil(8) { Self.topPresented(in: window) != nil }
        XCTAssertTrue(shown, "the login sheet never came up")
        XCTAssertEqual(OrientationController.shared.presentation, .inline)
        XCTAssertEqual(scene.effectiveGeometry.interfaceOrientation, .portrait, "the sheet went up over a rotated page")
        XCTAssertLessThan(window.bounds.width, window.bounds.height)
        let host = try XCTUnwrap(Self.hostView(in: window), "the player left the page")
        XCTAssertTrue(host.window === window)

        window.rootViewController?.dismiss(animated: false)
        let gone = await waitUntil(5) { window.rootViewController?.presentedViewController == nil }
        XCTAssertTrue(gone, "the login sheet did not go away")
        XCTAssertTrue(host.window === window, "the player left its window behind the login sheet")
        XCTAssertEqual(OrientationController.shared.presentation, .inline)
    }

    // MARK: helpers

    private func openAndCloseCoinDialog(_ actions: ActionsModel, in window: UIWindow, landscape: Bool) async throws {
        XCTAssertEqual(window.bounds.width > window.bounds.height, landscape)
        actions.ask(.coin)
        let opened = await waitUntil(3) { Self.find(CoinDialog.identifier, in: window) != nil }
        XCTAssertTrue(opened, "the coin dialog did not open (landscape \(landscape))")
        XCTAssertEqual(prompts.overlay, .coin)
        let balance = await waitUntil(3) { prompts.balance == 873 }
        XCTAssertTrue(balance, "the balance never arrived")
        try await Task.sleep(for: .milliseconds(500))

        let probe = try XCTUnwrap(Self.find(CoinDialog.identifier, in: window))
        let frame = probe.convert(probe.bounds, to: window)
        XCTAssertEqual(frame.width, window.bounds.width, accuracy: 1, "the dialog should cover the screen: \(frame)")
        XCTAssertEqual(frame.height, window.bounds.height, accuracy: 1, "the dialog should cover the screen: \(frame)")

        let size = window.bounds.size
        // Above the crates upright; beside the centred column turned.
        let outside = landscape ? CGPoint(x: size.width * 0.08, y: size.height / 2) : CGPoint(x: size.width / 2, y: size.height * 0.15)
        let hit = window.hitTest(outside, with: nil)
        let catcher = try XCTUnwrap(hit as? TapCatcherView, "a tap outside the dialog reaches \(String(describing: hit))")
        let crates = CGPoint(x: size.width / 2, y: landscape ? size.height / 2 : size.height * Theme.Coin.cardsCentre)
        XCTAssertFalse(window.hitTest(crates, with: nil) is TapCatcherView, "a tap on the dialog would close it")

        _ = catcher.accessibilityActivate()
        let gone = await waitUntil(3) { Self.find(CoinDialog.identifier, in: window) == nil }
        XCTAssertTrue(gone, "the coin dialog did not close (landscape \(landscape))")
        XCTAssertNil(prompts.overlay)
    }

    private func showPage() async throws -> UIWindow {
        let scene = try XCTUnwrap(Self.scene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: PromptsHarness(prompts: prompts).environment(AppEnvironment(http: http)))
        window.makeKeyAndVisible()
        self.window = window
        let laidOut = await waitUntil(5) { (window.rootViewController?.view.bounds.width ?? 0) > 0 }
        XCTAssertTrue(laidOut, "the page never laid out")
        return window
    }

    private func pageActions() async throws -> ActionsModel {
        let made = await waitUntil(8) { prompts.actions != nil }
        XCTAssertTrue(made, "the page never made its actions")
        return try XCTUnwrap(prompts.actions)
    }

    private func turnToLandscape() async throws {
        let scene = try XCTUnwrap(Self.scene)
        OrientationController.shared.enterLandscape()
        let turned = await waitUntil(8) { scene.effectiveGeometry.interfaceOrientation.isLandscape }
        XCTAssertTrue(turned, "the scene never turned to landscape")
        _ = await waitUntil(3) { (self.window?.bounds.width ?? 0) > (self.window?.bounds.height ?? 0) }
    }

    private func assertStillLandscape(in window: UIWindow) throws {
        let scene = try XCTUnwrap(Self.scene)
        XCTAssertTrue(scene.effectiveGeometry.interfaceOrientation.isLandscape)
        XCTAssertEqual(OrientationController.shared.presentation, .landscape)
        let host = try XCTUnwrap(Self.hostView(in: window), "the player left the page")
        XCTAssertTrue(host.window === window, "the player left its window")
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

    private static func topPresented(in window: UIWindow) -> UIViewController? {
        var top = window.rootViewController?.presentedViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    private static func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for subview in view.subviews {
            if let found = find(identifier, in: subview) { return found }
        }
        return nil
    }

    private static func hostView(in view: UIView) -> PlayerHostView? {
        if let host = view as? PlayerHostView { return host }
        for subview in view.subviews {
            if let host = hostView(in: subview) { return host }
        }
        return nil
    }
}
