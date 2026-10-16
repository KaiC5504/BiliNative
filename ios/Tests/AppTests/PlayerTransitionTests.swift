import AVKit
import SwiftUI
import XCTest
@testable import BiliNative

/// Build 1 crashed when AVKit moved its views into a full-screen controller. The custom surface rotates the
/// page itself and starts picture in picture from its own layer, so these perform both on the simulator.
@MainActor
final class PlayerTransitionTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        let orientation = OrientationController.shared
        orientation.locked = false
        orientation.videoIsVertical = false
        orientation.exitToInline()
        if let scene = Self.scene {
            _ = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        }
        window?.isHidden = true
        window = nil
    }

    func testEnterAndLeaveLandscapeWithTheSurfaceOnScreen() async throws {
        let scene = try XCTUnwrap(Self.scene)
        let host = try await showSurface(player: AVPlayer())
        let portraitWidth = host.bounds.width
        let orientation = OrientationController.shared

        orientation.enterLandscape()
        XCTAssertEqual(orientation.presentation, .landscape)
        XCTAssertEqual(orientation.mask, .landscape)
        let turned = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation.isLandscape }
        XCTAssertTrue(turned, "the scene never turned to landscape")
        let relaid = await waitUntil(3) { host.bounds.width > portraitWidth }
        XCTAssertTrue(relaid, "the surface was not laid out for landscape")
        XCTAssertTrue(host.window === window, "the surface left its window while rotating")
        XCTAssertEqual(host.videoView.bounds.size, host.bounds.size)

        orientation.exitToInline()
        XCTAssertEqual(orientation.presentation, .inline)
        XCTAssertEqual(orientation.mask, .portrait)
        let back = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        XCTAssertTrue(back, "the scene never turned back to portrait")
        XCTAssertTrue(host.window === window)
    }

    func testVerticalVideoIgnoresTurningAndLockHolds() {
        let orientation = OrientationController.shared
        orientation.videoIsVertical = true
        orientation.deviceOrientationChanged(.landscapeLeft)
        XCTAssertEqual(orientation.presentation, .inline, "turning the phone does nothing for a vertical video")

        orientation.videoIsVertical = false
        orientation.enterLandscape()
        orientation.locked = true
        orientation.deviceOrientationChanged(.portrait)
        XCTAssertEqual(orientation.presentation, .landscape, "the rotation lock holds landscape")

        orientation.locked = false
        orientation.deviceOrientationChanged(.landscapeLeft)
        orientation.deviceOrientationChanged(.portrait)
        XCTAssertEqual(orientation.presentation, .inline)
        orientation.deviceOrientationChanged(.landscapeRight)
        XCTAssertEqual(orientation.presentation, .landscape)
    }

    func testLandscapeByTheButtonWaitsForARealTurnBeforePortraitExits() throws {
        try XCTSkipIf(UIDevice.current.orientation.isLandscape, "the simulator reports a landscape device")
        let orientation = OrientationController.shared
        orientation.enterLandscape()
        orientation.deviceOrientationChanged(.faceUp)
        orientation.deviceOrientationChanged(.portrait)
        XCTAssertEqual(orientation.presentation, .landscape, "lifting the phone off the table leaves full screen")

        orientation.deviceOrientationChanged(.landscapeLeft)
        orientation.deviceOrientationChanged(.portrait)
        XCTAssertEqual(orientation.presentation, .inline, "turning back to portrait after a real turn stays in full screen")
    }

    func testRefusedRotationGoesBackInline() async throws {
        _ = try XCTUnwrap(Self.scene)
        let orientation = OrientationController.shared
        let original = orientation.requestGeometry
        defer { orientation.requestGeometry = original }
        orientation.requestGeometry = { _, _, refused in refused(CocoaError(.featureUnsupported)) }

        orientation.enterLandscape()
        XCTAssertEqual(orientation.presentation, .landscape)
        let reverted = await waitUntil(2) { orientation.presentation == .inline }
        XCTAssertTrue(reverted, "a refused rotation left the page in landscape")
        XCTAssertEqual(orientation.mask, .portrait)
    }

    func testEndForgetsTheVerticalVideo() {
        let orientation = OrientationController.shared
        orientation.videoIsVertical = true
        orientation.locked = true
        orientation.end()
        XCTAssertFalse(orientation.videoIsVertical)
        XCTAssertFalse(orientation.locked)
    }

    func testPictureInPictureControllerExistsAndStartsWhenSupported() async throws {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            throw XCTSkip("picture in picture is not supported on this simulator")
        }
        guard let directory = ProcessInfo.processInfo.environment["MEDIA_DIR"] else {
            throw XCTSkip("MEDIA_DIR not set; CI generates it with ios/scripts/make_test_media.py")
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("avc-video.mp4")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("no \(url.lastPathComponent) in MEDIA_DIR")
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        defer { player.pause() }
        let host = try await showSurface(player: player)
        let pip = try XCTUnwrap(host.pip, "a layer with a player should get a picture-in-picture controller")
        XCTAssertTrue(pip.canStartPictureInPictureAutomaticallyFromInline)

        player.play()
        guard await waitUntil(15, { pip.isPictureInPicturePossible }) else {
            let status = player.currentItem?.status.rawValue ?? -1
            throw XCTSkip("picture in picture never became possible here (item status \(status), "
                          + "error \(String(describing: player.currentItem?.error)))")
        }
        host.startPiP()
        let settled = await waitUntil(10) { pip.isPictureInPictureActive || host.pipError != nil }
        if let error = host.pipError {
            throw XCTSkip("picture in picture refused to start on this simulator: \(error)")
        }
        XCTAssertTrue(settled && pip.isPictureInPictureActive, "picture in picture did not start")

        pip.stopPictureInPicture()
        let stopped = await waitUntil(10) { !pip.isPictureInPictureActive }
        XCTAssertTrue(stopped, "picture in picture did not stop")
        XCTAssertTrue(host.window === window, "the surface left its window during picture in picture")
    }

    func testVerticalPansAreRefusedInlineAndAcceptedInFullScreen() {
        let pan = SyntheticPan(target: nil, action: nil)
        let view = PlayerGestureView(pan: pan)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 221)

        pan.synthetic = CGPoint(x: 3, y: 24)
        XCTAssertFalse(view.gestureRecognizerShouldBegin(pan), "a vertical drag in the small player belongs to the page")
        pan.synthetic = CGPoint(x: -24, y: 3)
        XCTAssertTrue(view.gestureRecognizerShouldBegin(pan), "a horizontal drag seeks in the small player too")
        pan.synthetic = CGPoint(x: 4, y: 4)
        XCTAssertTrue(view.gestureRecognizerShouldBegin(pan), "short of the lock distance a tie counts as horizontal")

        view.allowsLevelGestures = true
        pan.synthetic = CGPoint(x: 3, y: -24)
        XCTAssertTrue(view.gestureRecognizerShouldBegin(pan), "a vertical drag sets brightness or volume in full screen")

        let screen = CGRect(x: 0, y: 0, width: 852, height: 393)
        XCTAssertTrue(PlayerGestureView.isNearEdge(CGPoint(x: 10, y: 200), of: screen))
        XCTAssertTrue(PlayerGestureView.isNearEdge(CGPoint(x: 400, y: 380), of: screen))
        XCTAssertFalse(PlayerGestureView.isNearEdge(CGPoint(x: 400, y: 200), of: screen))
    }

    private func showSurface(player: AVPlayer?) async throws -> PlayerHostView {
        let scene = try XCTUnwrap(Self.scene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            PlayerSurface(player: player).aspectRatio(16 / 9, contentMode: .fit))
        window.makeKeyAndVisible()
        self.window = window
        var found: PlayerHostView?
        _ = await waitUntil(5) {
            found = Self.hostView(in: window)
            return found.map { $0.bounds.width > 0 } ?? false
        }
        return try XCTUnwrap(found, "the surface never appeared")
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

    private static func hostView(in view: UIView) -> PlayerHostView? {
        if let host = view as? PlayerHostView { return host }
        for subview in view.subviews {
            if let host = hostView(in: subview) { return host }
        }
        return nil
    }
}

private final class SyntheticPan: UIPanGestureRecognizer {
    var synthetic = CGPoint.zero

    override func translation(in view: UIView?) -> CGPoint { synthetic }
}
