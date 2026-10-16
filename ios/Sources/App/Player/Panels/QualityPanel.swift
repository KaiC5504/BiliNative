import SwiftUI
import AppLogic
import BiliAPI

/// 清晰度 (05): 自动 and every quality the playurl offered, best first.
struct QualityPanel: View {
    let model: VideoPageModel
    let isVip: Bool
    let openCodec: () -> Void
    let toast: (String) -> Void
    let close: () -> Void

    /// The official app's names, which differ from the playurl's descriptions ("超清 4K", "高清 1080P").
    static func title(for option: QualityOption) -> String {
        switch option.id {
        case 127: "8K 超高清"
        case 126: "杜比视界"
        case 125: "HDR 真彩"
        case 120: "4K 超高清"
        case 116: "1080P 60帧"
        case 112: "1080P+ 高码率"
        case 80: "1080P 高清"
        case 74: "720P 60帧"
        case 64: "720P 准高清"
        case 32: "480P 清晰"
        case 16: "360P 流畅"
        default: option.name
        }
    }

    static func subtitle(for option: QualityOption) -> String? {
        option.id == 125 ? "绚丽色彩，沉浸体验" : nil
    }

    var body: some View {
        let controller = model.controller
        let options = (controller?.qualities ?? []).sorted { $0.id > $1.id }
        let playing = controller?.playingQuality ?? controller?.selectedQuality
        VStack(spacing: PanelMetrics.gap) {
            PanelHeader(title: "清晰度") {
                Button(action: openCodec) {
                    HStack(spacing: 2) {
                        Text("高级设置")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.panelSecondary)
                    .padding(.trailing, 4)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            PanelCardRow(title: "自动") { chooseAuto(options) }
            ForEach(options, id: \.id) { option in
                PanelCardRow(title: Self.title(for: option), subtitle: Self.subtitle(for: option),
                             badge: QualityRules.needsVip(option.id) ? "大会员" : nil,
                             selected: option.id == playing) { choose(option) }
            }
        }
        .padding(.top, 15)
    }

    private func chooseAuto(_ options: [QualityOption]) {
        guard let best = QualityRules.auto(offered: options.map(\.id), isVip: isVip) else { return }
        apply(best)
    }

    private func choose(_ option: QualityOption) {
        if QualityRules.needsVip(option.id), !isVip {
            toast("开通大会员后可观看")
            return
        }
        apply(option.id)
    }

    private func apply(_ quality: Int) {
        model.settings.preferredQuality = quality
        if let controller = model.controller {
            Task { await controller.setQuality(quality) }
        }
        close()
    }
}

/// 高级设置 > from the 清晰度 panel: which codec the engine asks Bilibili for.
struct CodecPanel: View {
    let model: VideoPageModel
    let back: () -> Void
    let close: () -> Void

    static func title(for codec: VideoCodec) -> String {
        switch codec {
        case .hevc: "HEVC"
        case .av1: "AV1"
        case .avc: "AVC"
        }
    }

    var body: some View {
        let current = model.settings.preferredCodec
        VStack(spacing: PanelMetrics.gap) {
            PanelHeader(title: "高级设置", back: back)
            ForEach(VideoCodec.allCases, id: \.self) { codec in
                PanelCardRow(title: Self.title(for: codec), selected: codec == current) { choose(codec) }
            }
        }
        .padding(.top, 15)
    }

    private func choose(_ codec: VideoCodec) {
        model.settings.preferredCodec = codec
        if let controller = model.controller {
            Task { await controller.setCodec(codec) }
        }
        close()
    }
}
