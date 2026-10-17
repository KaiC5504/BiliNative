#if DEBUG
import Foundation
import UIKit

/// `-DemoScreen leak-check`: opens a video page, goes back after it has played a while, and writes the addresses
/// of whatever from that page is still alive to Documents/leak-check.txt. The compile workflow's leak step runs
/// macOS `leaks --traceTree` on each address, which shows what holds it.
@MainActor
enum LeakCheckDemo {
    static let screen = "leak-check"
    static let fileName = "leak-check.txt"

    static func stage(navigator: AppNavigator) {
        guard UserDefaults.standard.string(forKey: "DemoScreen") == screen else { return }
        navigator.open(VideoRoute(bvid: VideoPageFixtures.bvidA))
        Task {
            try? await Task.sleep(for: .seconds(6))
            weak var page = OrientationController.shared.owner as? VideoPageModel
            weak var host = page?.host
            weak var danmaku = page?.host?.danmakuContainer.subviews.first
            navigator.path = []
            try? await Task.sleep(for: .seconds(5))
            var lines: [String] = []
            for (name, object) in [("VideoPageModel", page as AnyObject?), ("PlayerHostView", host), ("DanmakuView", danmaku)] {
                guard let object else { continue }
                lines.append("\(name) \(Unmanaged.passUnretained(object).toOpaque())")
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
