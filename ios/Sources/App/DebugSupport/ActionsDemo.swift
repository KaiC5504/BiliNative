#if DEBUG
import Foundation

/// The compile check's photographs of the actions: `page-actions-active` (03 with 点赞, 投币 and 收藏 on) and
/// `player-landscape-actions` (04 with the same state in the top bar).
@MainActor
enum ActionsDemo {
    private typealias F = VideoPageFixtures

    nonisolated static let screens: Set<String> = [ActionsFixtures.activeScreen, "player-landscape-actions"]

    static func route(for name: String?) -> VideoRoute? {
        guard let name, screens.contains(name) else { return nil }
        return VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 7)
    }

    private static var staged = false

    static func stage(page: VideoPageModel, chrome: ChromeState) {
        let name = UserDefaults.standard.string(forKey: "DemoScreen")
        guard !staged, let name, screens.contains(name) else { return }
        staged = true
        chrome.autoHides = false
        page.settings.showOverlay = false
        Task {
            for _ in 0..<150 {
                if page.controller?.phase == .playing, page.relation != nil, page.uploader != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // A moment for the first frames and the avatar.
            try? await Task.sleep(for: .milliseconds(1200))
            if name == "player-landscape-actions" {
                OrientationController.shared.enterLandscape()
            }
            page.pause()
            chrome.touch()
        }
    }
}
#endif
