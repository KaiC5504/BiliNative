#if DEBUG
import Foundation

/// The compile check's photographs of what 投币 and 收藏 open: `coin-dialog` (15) and `favourite-sheet`.
@MainActor
enum ActionPromptsDemo {
    private typealias F = VideoPageFixtures

    nonisolated static let screens: Set<String> = ["coin-dialog", "favourite-sheet"]

    static func route(for name: String?) -> VideoRoute? {
        guard let name, screens.contains(name) else { return nil }
        return VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 1)
    }

    private static var staged = false

    /// `actions` is read each time: the page makes its actions once the video has loaded.
    static func stage(page: VideoPageModel, chrome: ChromeState, actions: @escaping () -> ActionsModel?) {
        let name = UserDefaults.standard.string(forKey: "DemoScreen")
        guard !staged, let name, screens.contains(name) else { return }
        staged = true
        chrome.autoHides = false
        page.settings.showOverlay = false
        Task {
            for _ in 0..<100 {
                if page.controller?.phase == .playing, page.relation != nil, actions() != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(600))
            page.pause()
            chrome.touch()
            actions()?.ask(name == "coin-dialog" ? .coin : .favourites)
        }
    }
}
#endif
