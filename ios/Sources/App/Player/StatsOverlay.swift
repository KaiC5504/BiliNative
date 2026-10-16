import SwiftUI
import Ripper

struct StatsOverlay: View {
    let stats: OverlayStats
    let mode: PlaybackController.Mode
    var quality: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line("模式", mode.label)
            line("画质", quality ?? "-")
            line("首帧", stats.firstFrameMs.map { String(format: "%.2f 秒", $0 / 1000) } ?? "-")
            line("跳转恢复", stats.lastSeekMs.map { String(format: "%.2f 秒", $0 / 1000) } ?? "-")
            line("卡顿", "\(stats.stalls) 次")
            line("下载", String(format: "%.1f MB/s", stats.downloadBps / 1_048_576))
            if let ripper = stats.ripper {
                line("连接", "\(ripper.concurrency)  重复 \(String(format: "%.1f", ripper.duplicateShare * 100))%  缓存命中 \(ripper.cacheHits)")
                ForEach(ripper.nodes, id: \.node) { node in
                    let state = Resolver.NodeStatus.best(of: node.node, in: ripper.nodeStates)
                    HStack(spacing: 4) {
                        Circle().fill(Self.color(state?.state)).frame(width: 5, height: 5)
                        Text("\(shortName(node.node)) \(Int(node.firstByteMs))ms \(String(format: "%.1f", (state?.bps ?? 0) / 1_048_576))MB/s \(state?.state ?? "")")
                    }
                }
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .monospacedDigit()
        .contentTransition(.numericText())
        .animation(.snappy, value: stats)
        .animation(.snappy, value: mode)
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
        .padding(6)
        .allowsHitTesting(false)
    }

    private func line(_ label: String, _ value: String) -> some View {
        Text("\(label) \(value)")
    }

    private func shortName(_ node: String) -> String {
        node.replacingOccurrences(of: ".bilivideo.com", with: "").replacingOccurrences(of: "upos-sz-", with: "")
    }

    private static func color(_ state: String?) -> Color {
        switch state {
        case "healthy": return .green
        case "blocked": return .orange
        case "banned": return .red
        default: return .gray
        }
    }
}
