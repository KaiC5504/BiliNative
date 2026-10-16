import SwiftUI
import AVFoundation
import AppLogic
import BiliAPI

/// Landscape full screen (04). Laid out against the screen's safe-area `insets`, since the page itself ignores them.
struct LandscapeChrome: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    let insets: EdgeInsets
    let showsActions: Bool
    let danmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void
    let onBack: () -> Void
    /// The 评论 icon: back to the page with the 评论 tab showing.
    var onComments: () -> Void = {}

    @State private var toast: String?

    var body: some View {
        let orientation = OrientationController.shared
        ZStack {
            if chrome.visible && panel == nil {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Theme.Chrome.shade, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, Theme.Chrome.shade], startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomBar
                }
                .overlay(alignment: .trailing) {
                    VStack(spacing: 9) {
                        ChromeButton(systemName: "camera", label: "截图", font: .system(size: 20)) { capture() }
                        ChromeButton(systemName: orientation.locked ? "lock" : "lock.open", label: orientation.locked ? "解锁屏幕方向" : "锁定屏幕方向",
                                     font: .system(size: 20)) {
                            orientation.locked.toggle()
                            chrome.touch()
                        }
                    }
                    .padding(.trailing, insets.trailing - 1)
                    .offset(y: -15)
                }
                .transition(.opacity)
            } else if panel == nil, let online = model.online {
                // The official app keeps the viewer count faintly in the corner while the controls are hidden (25).
                OnlineLabel(text: "\(online)人正在看", font: .system(size: 11))
                    .foregroundStyle(Theme.Chrome.faint)
                    .padding(.leading, insets.leading + 33)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: chrome.visible)
        .toast($toast)
    }

    // MARK: top

    private var topBar: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ChromeButton(systemName: "chevron.left", label: "返回", action: onBack)
                        .frame(height: 30)
                    Text(title)
                        .font(Theme.Chrome.titleFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(height: 30)
                if let online = model.online {
                    OnlineLabel(text: "\(online)人正在看", font: Theme.Chrome.smallFont)
                        .foregroundStyle(Theme.Chrome.secondary)
                        .frame(height: 16)
                        .padding(.leading, 45)
                }
                if let owner = model.detail?.owner {
                    HStack(spacing: 9) {
                        RemoteImage(owner.face)
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                        if showsActions {
                            Text("+ 关注")
                                .font(Theme.Chrome.labelFont)
                                .foregroundStyle(.white)
                        } else {
                            Text(owner.name)
                                .font(Theme.Chrome.labelFont)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 24)
                    .padding(.leading, 11)
                    .padding(.top, 6)
                }
            }
            .padding(.top, 27)
            .padding(.leading, insets.leading + 5)
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                if showsActions, let stat = model.detail?.stat {
                    ActionIcon(systemName: "hand.thumbsup", count: stat.like)
                    Button(action: onComments) {
                        ActionIcon(systemName: "text.bubble", count: nil)
                    }
                    .accessibilityLabel("评论")
                    ActionIcon(systemName: "star", count: stat.favorite)
                    ActionIcon(coin: true, count: nil)
                    ActionIcon(systemName: "arrowshape.turn.up.right", count: nil)
                }
                MoreButton { panel = .more }
            }
            .padding(.top, 20)
            .padding(.trailing, insets.trailing + 5)
        }
    }

    private var title: String {
        guard let detail = model.detail else { return "" }
        // A multi-part video shows the part's title, as the official app does.
        if detail.pages.count > 1, let part = model.currentPage?.part, !part.isEmpty { return part }
        return detail.title
    }

    // MARK: bottom

    private var bottomBar: some View {
        let controller = model.controller
        let duration = controller?.duration ?? 0
        let position = chrome.scrubbing ?? controller?.position ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(TimeFormat.pair(position, duration))
                .font(Theme.Chrome.timeFont)
                .foregroundStyle(.white)
                .padding(.leading, 1)
            ProgressBar(position: position, duration: duration, buffered: controller?.buffered ?? 0,
                        chapters: model.chapters,
                        onScrub: { chrome.scrub(to: $0) },
                        onCommit: { chrome.commit($0, page: model) })
                .padding(.top, 15)
            HStack(spacing: 0) {
                PlayButton(model: model, font: Theme.Chrome.landscapePlayFont) { chrome.touch() }
                Button {
                    onToggleDanmaku()
                    chrome.touch()
                } label: {
                    danmakuGlyph(danmakuEnabled ? .danmakuOn : .danmakuOff)
                }
                .accessibilityLabel(danmakuEnabled ? "关闭弹幕" : "开启弹幕")
                .padding(.leading, 5)
                Button { panel = .danmakuSettings } label: {
                    danmakuGlyph(.danmakuSettings)
                }
                .accessibilityLabel("弹幕设置")
                .padding(.leading, 5)
                Button(action: onSendDanmaku) {
                    Text("发个友善的弹幕见证当下")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Chrome.fieldText)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 29)
                        .background(Theme.Chrome.field, in: Capsule())
                        .contentShape(Capsule())
                }
                .padding(.leading, 3)
                textButton("倍速") { panel = .speed }
                    .padding(.leading, 14)
                textButton(QualityLabel.short(controller), bold: true) { panel = .quality }
                    .padding(.leading, 23)
                if hasEpisodes {
                    textButton("选集") { panel = .episodes }
                        .padding(.leading, 15)
                }
            }
            .padding(.top, 4)
            .padding(.trailing, 15)
        }
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        .padding(.bottom, insets.bottom)
    }

    private var hasEpisodes: Bool {
        guard let detail = model.detail else { return false }
        return detail.pages.count > 1 || detail.season != nil
    }

    private func danmakuGlyph(_ icon: BorrowedIcon) -> some View {
        icon.image
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .frame(width: 25, height: 25)
            .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
            .contentShape(Rectangle())
    }

    private func textButton(_ text: String, bold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(bold ? Theme.Chrome.labelFont.weight(.bold) : Theme.Chrome.labelFont)
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: Theme.Chrome.button)
                .contentShape(Rectangle())
        }
    }

    private func capture() {
        chrome.touch()
        guard let item = model.controller?.player.currentItem, let image = FrameCapture.capture(from: item) else {
            toast = "保存失败"
            return
        }
        Task {
            toast = await FrameCapture.saveToPhotos(image) ? "已保存到相册" : "保存失败"
        }
    }
}

/// The two-person outline and "N人正在看".
struct OnlineLabel: View {
    let text: String
    let font: Font

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2")
                .font(font)
            Text(text)
                .font(font)
                .lineLimit(1)
        }
    }
}

/// A top-bar action with its count as a superscript (04), behind `showsActions`.
struct ActionIcon: View {
    var systemName: String = ""
    var coin = false
    let count: Int64?

    var body: some View {
        Group {
            if coin {
                CoinGlyph(filled: false)
                    .frame(width: 21, height: 21)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 20))
            }
        }
        .foregroundStyle(.white)
        .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
        .overlay(alignment: .topTrailing) {
            if let count, count > 0 {
                Text(CountFormat.short(count))
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .offset(x: 2, y: 2)
            }
        }
    }
}

/// 投币's coin: a circle with 币 in it, outlined in the top bar and filled in the 竖屏 column.
struct CoinGlyph: View {
    let filled: Bool

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                if filled {
                    Circle().fill(.white)
                    Text("币")
                        .font(.system(size: side * 0.6, weight: .bold))
                        .foregroundStyle(.black)
                } else {
                    Circle().stroke(.white, lineWidth: side * 0.09)
                    Text("币")
                        .font(.system(size: side * 0.55, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
        }
    }
}

/// The quality button's short label: 4K, 1080P+, HDR …
@MainActor
enum QualityLabel {
    static func short(_ controller: PlaybackControlling?) -> String {
        guard let controller else { return "清晰度" }
        let id = controller.playingQuality ?? controller.selectedQuality
        return QualityNames.short(qn: id, serverText: controller.qualities.first { $0.id == id }?.name)
    }
}
