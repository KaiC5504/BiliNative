#if DEBUG
import Foundation

/// The compile check's photographs of the 简介: `page-intro` (03), `page-intro-expanded` (18), `sheet-collection` (19)
/// and `page-collapsed` (12). They open the 合集's second episode, a single-part video, and pause it once it plays.
@MainActor
enum IntroDemo {
    private typealias F = VideoPageFixtures

    nonisolated private static let screens: Set<String> = ["page-intro", "page-intro-expanded", "sheet-collection", "page-collapsed"]

    nonisolated private static var screen: String? {
        UserDefaults.standard.string(forKey: "DemoScreen").flatMap { screens.contains($0) ? $0 : nil }
    }

    static func route(for name: String?) -> VideoRoute? {
        guard let name, screens.contains(name) else { return nil }
        return VideoRoute(bvid: F.bvidB, cid: F.cidB, startSeconds: 20)
    }

    nonisolated static var expandsTitle: Bool { screen == "page-intro-expanded" }

    private static var staged = false

    static func stage(page: VideoPageModel, tabs: PageTabsState) {
        guard !staged, let screen else { return }
        staged = true
        page.settings.showOverlay = false
        Task {
            for _ in 0..<150 {
                if page.controller?.phase == .playing, !page.related.isEmpty, page.uploader != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // A moment for the first frames and the covers.
            try? await Task.sleep(for: .milliseconds(1500))
            page.pause()
            switch screen {
            case "sheet-collection":
                tabs.sheet = .collection
            case "page-collapsed":
                tabs.scroll(.intro, toY: 420)
            default:
                break
            }
        }
    }
}
#endif
