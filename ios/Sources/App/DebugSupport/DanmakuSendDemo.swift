#if DEBUG
import Foundation

/// The compile check's photographs of the danmaku input (22 and 23): the demo video in landscape, paused,
/// with the send bar open over a stand-in keyboard or over the style panel. `danmaku-send-inline` opens the bar
/// from the small player's page instead, as 点我发弹幕 in the tab row does.
@MainActor
enum DanmakuSendDemo {
    private static var staged = false

    static func route(for name: String?) -> VideoRoute? {
        guard name == "danmaku-send-inline" else { return nil }
        return VideoRoute(bvid: VideoPageFixtures.bvidA, cid: VideoPageFixtures.cidA1, startSeconds: 20)
    }

    static func stage(page: VideoPageModel, chrome: ChromeState, open: @escaping (DanmakuSendBar.Demo) -> Void) {
        let name = UserDefaults.standard.string(forKey: "DemoScreen")
        guard !staged, name == "danmaku-send" || name == "danmaku-style" || name == "danmaku-send-inline" else { return }
        staged = true
        chrome.autoHides = false
        page.settings.showOverlay = false
        let inline = name == "danmaku-send-inline"
        Task {
            for _ in 0..<150 {
                if page.controller?.phase == .playing { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(1500))
            if !inline { OrientationController.shared.enterLandscape() }
            page.pause()
            chrome.touch()
            // The rotation has to finish first, or the bar is laid out for portrait.
            if !inline { try? await Task.sleep(for: .seconds(2)) }
            open(name == "danmaku-style" ? .style : .keyboard)
        }
    }
}
#endif
