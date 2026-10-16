#if DEBUG
import Foundation

/// The compile check's photographs of the danmaku input (22 and 23): the demo video in landscape, paused,
/// with the send bar open over a stand-in keyboard or over the style panel.
@MainActor
enum DanmakuSendDemo {
    private static var staged = false

    static func stage(page: VideoPageModel, chrome: ChromeState, open: @escaping (DanmakuSendBar.Demo) -> Void) {
        let name = UserDefaults.standard.string(forKey: "DemoScreen")
        guard !staged, name == "danmaku-send" || name == "danmaku-style" else { return }
        staged = true
        chrome.autoHides = false
        page.settings.showOverlay = false
        Task {
            for _ in 0..<150 {
                if page.controller?.phase == .playing { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(1500))
            OrientationController.shared.enterLandscape()
            page.pause()
            chrome.touch()
            // The rotation has to finish first, or the bar is laid out for portrait.
            try? await Task.sleep(for: .seconds(2))
            open(name == "danmaku-style" ? .style : .keyboard)
        }
    }
}
#endif
