#if DEBUG
import Foundation

/// The compile check's photographs of the 评论 tab: `comments` (10), `comments-thread` (13), `picture-viewer` and
/// `composer-emotes` (14). They open the demo video, switch to 评论 once the list can load, and open a thread, the
/// pictures or the composer.
@MainActor
enum CommentsDemo {
    private typealias F = VideoPageFixtures

    nonisolated private static let screens: Set<String> = ["comments", "comments-thread", "picture-viewer", "composer-emotes"]

    nonisolated private static var screen: String? {
        UserDefaults.standard.string(forKey: "DemoScreen").flatMap { screens.contains($0) ? $0 : nil }
    }

    /// `composer-emotes` (14) photographs the composer, which must not wait for a keyboard the simulator never shows.
    nonisolated static var isComposerDemo: Bool { screen == "composer-emotes" }

    static func route(for name: String?) -> VideoRoute? {
        guard let name, screens.contains(name) else { return nil }
        return VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 20)
    }

    private static var staged = false

    static func stage(page: VideoPageModel, tabs: PageTabsState, comments: @escaping () -> CommentsModel?,
                      compose: @escaping (ReplyTarget, Bool) -> Void) {
        guard !staged, let screen else { return }
        staged = true
        page.settings.showOverlay = false
        Task {
            for _ in 0..<150 {
                if page.controller?.phase == .playing, comments() != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            tabs.selection = .comments
            guard let model = comments() else { return }
            for _ in 0..<50 {
                if !model.comments.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // The avatars, pendants and emotes.
            try? await Task.sleep(for: .milliseconds(800))
            switch screen {
            case "comments-thread", "composer-emotes":
                // As in 13: paused and scrolled, so the player is down to its bar.
                page.pause()
                tabs.scroll(.comments, toY: 480)
                guard let root = model.comments.first(where: { $0.rpid == CommentFixtures.threadRoot }) else { return }
                await model.openThread(root)
                guard screen == "composer-emotes" else { return }
                // As in 14: replying to the thread's root, on the emote panel, with something used before.
                RecentEmotes.record(ComposerFixtures.recent)
                try? await Task.sleep(for: .milliseconds(500))
                compose(.comment(model.thread?.root ?? root), true)
            case "picture-viewer":
                guard let own = model.comments.first(where: { $0.rpid == CommentFixtures.ownComment }) else { return }
                model.viewing = PictureViewing(pictures: own.pictures, index: 1)
            default:
                break
            }
        }
    }
}
#endif
