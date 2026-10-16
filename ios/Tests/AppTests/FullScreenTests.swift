import AVKit
import SwiftUI
import XCTest
@testable import BiliNative

/// The full-screen button crashed build 1 on the phone. CI can't tap AVKit's own button, so this goes through
/// AVKit's private entry point, which the button calls too.
@MainActor
final class FullScreenTests: XCTestCase {
    private typealias FullScreenCall = @convention(c) (AnyObject, Selector, Bool, (@convention(block) (Bool) -> Void)?) -> Void

    func testEnteringAndLeavingFullScreenWithTheOverlay() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let overlay = AnyView(Text("1080P 高清 · HEVC · 2.1 Mbps").foregroundStyle(.white))
        window.rootViewController = UIHostingController(rootView:
            VideoPlayerView(player: AVPlayer(), overlay: overlay).aspectRatio(16 / 9, contentMode: .fit))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var found: AVPlayerViewController?
        for _ in 0..<50 where found == nil {
            try await Task.sleep(for: .milliseconds(100))
            found = Self.playerController(in: window.rootViewController)
        }
        let controller = try XCTUnwrap(found, "AVPlayerViewController never appeared")

        try await call("enterFullScreenAnimated:completionHandler:", on: controller)
        XCTAssertNotNil(controller.presentedViewController, "full screen did not present")
        try await Task.sleep(for: .milliseconds(500))
        try await call("exitFullScreenAnimated:completionHandler:", on: controller)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(controller.presentedViewController)
    }

    private func call(_ name: String, on controller: AVPlayerViewController) async throws {
        let selector = NSSelectorFromString(name)
        guard controller.responds(to: selector) else { throw XCTSkip("AVPlayerViewController has no \(name)") }
        let function = unsafeBitCast(controller.method(for: selector), to: FullScreenCall.self)
        let done = expectation(description: name)
        function(controller, selector, true) { _ in done.fulfill() }
        await fulfillment(of: [done], timeout: 10)
    }

    private static func playerController(in controller: UIViewController?) -> AVPlayerViewController? {
        guard let controller else { return nil }
        if let player = controller as? AVPlayerViewController { return player }
        return controller.children.lazy.compactMap { playerController(in: $0) }.first
    }
}
