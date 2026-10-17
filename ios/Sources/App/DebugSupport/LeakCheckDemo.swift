#if DEBUG
import Foundation
import UIKit

/// `-DemoScreen leak-check`: opens a video page, goes back after it has played a while, and writes the addresses
/// of whatever from that page is still alive to Documents/leak-check.txt, and who holds the page to
/// Documents/leak-report.txt (`HeapReferrers`). The compile workflow's leak step prints both.
@MainActor
enum LeakCheckDemo {
    static let screen = "leak-check"
    static let fileName = "leak-check.txt"
    static let reportName = "leak-report.txt"

    private static func address(_ object: AnyObject?) -> UInt? {
        object.map { UInt(bitPattern: Unmanaged.passUnretained($0).toOpaque()) }
    }

    static func stage(navigator: AppNavigator) {
        guard UserDefaults.standard.string(forKey: "DemoScreen") == screen else { return }
        navigator.open(VideoRoute(bvid: VideoPageFixtures.bvidA))
        Task {
            try? await Task.sleep(for: .seconds(6))
            weak var page = OrientationController.shared.owner as? VideoPageModel
            weak var host = page?.host
            weak var danmaku = page?.host?.danmakuContainer.subviews.first
            navigator.path = []
            // Past PageLifecycle's settle retries (up to 10 s), which hold the page while a transition runs.
            try? await Task.sleep(for: .seconds(12))
            var lines: [String] = []
            for (name, address) in [("VideoPageModel", address(page)), ("PlayerHostView", address(host)),
                                    ("DanmakuView", address(danmaku))] {
                guard let address else { continue }
                lines.append("\(name) 0x\(String(address, radix: 16))")
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? (lines.joined(separator: "\n") + "\n").write(to: documents.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            // Only the address goes on: a reference held here would show up as a holder.
            let report = address(page).map { HeapReferrers.report(forAddress: $0, label: "VideoPageModel") } ?? "nothing left alive"
            try? report.write(to: documents.appendingPathComponent(reportName), atomically: true, encoding: .utf8)
        }
    }
}
#endif
