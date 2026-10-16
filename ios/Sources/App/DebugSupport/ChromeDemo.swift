#if DEBUG
import Foundation
import AppLogic

/// The compile check's photographs of the player chrome: `-DemoData YES -DemoScreen <name>` opens the demo
/// video and stages it once it plays.
@MainActor
enum ChromeDemo {
    private typealias F = VideoPageFixtures

    /// The demo screens that open a video page and are not listed in HomeView.
    static func route(for name: String?) -> VideoRoute? {
        chromeRoute(for: name) ?? IntroDemo.route(for: name) ?? DanmakuSendDemo.route(for: name)
    }

    private static func chromeRoute(for name: String?) -> VideoRoute? {
        switch name {
        case "player-portrait": return VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 32)
        case "player-landscape": return VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 7)
        case "player-vertical": return VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 12)
        case "hud-speed": return VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 3)
        // The last 合集 episode, so the end has nothing to play next.
        case "end-portrait", "end-landscape": return VideoRoute(bvid: F.bvidC, cid: F.cidC, startSeconds: 30)
        default: return nil
        }
    }

    private static var staged = false

    static func stage(page: VideoPageModel, chrome: ChromeState) {
        let name = UserDefaults.standard.string(forKey: "DemoScreen")
        guard !staged, chromeRoute(for: name) != nil, let name else { return }
        staged = true
        chrome.autoHides = false
        page.settings.showOverlay = false
        Task {
            guard await playing(page) else { return }
            // The test media is 40 s long; the fixture's 200 s puts its chapter marks on the bar.
            (page.controller as? DemoPlayback)?.nominalDuration = 200
            let orientation = OrientationController.shared
            switch name {
            case "player-landscape":
                orientation.enterLandscape()
                page.pause()
                chrome.touch()
            case "player-vertical":
                orientation.enterVertical()
                page.pause()
                chrome.touch()
            case "hud-speed":
                orientation.enterLandscape()
                chrome.handle(.holdBegan, page: page, size: .zero)
            case "end-portrait":
                page.pause()
                await page.handleEnd()
            case "end-landscape":
                orientation.enterLandscape()
                page.pause()
                await page.handleEnd()
            default:
                page.pause()
                chrome.touch()
            }
        }
    }

    private static func playing(_ page: VideoPageModel) async -> Bool {
        for _ in 0..<150 {
            if let controller = page.controller, controller.phase == .playing, !page.related.isEmpty {
                // A moment for the first frames, so the photograph has a picture under the controls.
                try? await Task.sleep(for: .milliseconds(1500))
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
#endif
