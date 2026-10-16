import SwiftUI
import AppLogic
import BiliAPI

/// 竖屏 full screen (09): the page stays portrait and black, the controls sit around the video.
struct VerticalChrome: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    let insets: EdgeInsets
    let showsActions: Bool
    let danmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void
    let onBack: () -> Void

    var body: some View {
        let controller = model.controller
        let duration = controller?.duration ?? 0
        let position = chrome.scrubbing ?? controller?.position ?? 0
        ZStack {
            if chrome.visible && panel == nil {
                VStack(spacing: 0) {
                    topRow
                        .padding(.top, max(insets.top - 8, 0))
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 0) {
                        info
                            .padding(.leading, 12)
                            .padding(.trailing, showsActions ? 12 : 82)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showsActions, let stat = model.detail?.stat {
                            actionColumn(stat)
                                .padding(.trailing, 6)
                        }
                    }
                    ProgressBar(position: position, duration: duration, buffered: controller?.buffered ?? 0,
                                chapters: model.chapters, style: .dot,
                                onScrub: { chrome.scrub(to: $0) },
                                onCommit: { chrome.commit($0, page: model) })
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    bottomRow
                        .padding(.top, -3)
                        .padding(.bottom, insets.bottom)
                }
                .transition(.opacity)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: chrome.visible)
    }

    private var topRow: some View {
        HStack(spacing: 0) {
            ChromeButton(systemName: "chevron.left", label: "返回", action: onBack)
            if let online = model.online {
                OnlineLabel(text: "\(online)人正在看", font: Theme.Chrome.smallFont.weight(.medium))
                    .foregroundStyle(Theme.Chrome.secondary)
                    .padding(.leading, 8)
            }
            Spacer(minLength: 0)
            MoreButton { panel = .more }
        }
    }

    @ViewBuilder
    private var info: some View {
        if let detail = model.detail {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RemoteImage(detail.owner.face)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    Text(detail.owner.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.pink)
                        .lineLimit(1)
                    if showsActions {
                        Text("+ 关注")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Theme.pink, in: Capsule())
                    }
                }
                titleLine(detail)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .lineSpacing(3)
            }
        }
    }

    /// The title runs on into "5.6万播放 ⌄" in a smaller size, as in 09.
    private func titleLine(_ detail: VideoDetail) -> Text {
        let title = Text(verbatim: detail.title)
        let views = Text(verbatim: "  \(CountFormat.short(detail.stat.view))播放")
            .font(.system(size: 14))
            .foregroundStyle(Theme.Chrome.secondary)
        let chevron = Text(Image(systemName: "chevron.down"))
            .font(.system(size: 11))
            .foregroundStyle(Theme.Chrome.secondary)
        return Text("\(title)\(views)\(chevron)")
    }

    private func actionColumn(_ stat: VideoStat) -> some View {
        VStack(spacing: 15) {
            columnItem(Image(systemName: "hand.thumbsup.fill"), stat.like)
            columnItem(Image(systemName: "ellipsis.bubble.fill"), stat.reply)
            VStack(spacing: 6) {
                CoinGlyph(filled: true)
                    .frame(width: 30, height: 30)
                countText(stat.coin)
            }
            columnItem(Image(systemName: "star.fill"), stat.favorite)
            columnItem(Image(systemName: "arrowshape.turn.up.right.fill"), stat.share)
        }
        .frame(width: 44)
    }

    private func columnItem(_ icon: Image, _ count: Int64) -> some View {
        VStack(spacing: 6) {
            icon
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(height: 30)
            countText(count)
        }
    }

    private func countText(_ count: Int64) -> some View {
        Text(CountFormat.short(count))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: onSendDanmaku) {
                    Text("发弹幕")
                        .font(Theme.Chrome.labelFont)
                        .foregroundStyle(Theme.Chrome.darkFieldText)
                        .padding(.leading, 15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                Rectangle()
                    .fill(Theme.Chrome.divider)
                    .frame(width: 1, height: 18)
                Button(action: onToggleDanmaku) {
                    (danmakuEnabled ? BorrowedIcon.danmakuOn : BorrowedIcon.danmakuOff).image
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .frame(width: 50, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(danmakuEnabled ? "关闭弹幕" : "开启弹幕")
            }
            .frame(height: 32)
            .background(Theme.Chrome.darkField, in: Capsule())
            .padding(.leading, 12)
            Button {
                chrome.touch()
                OrientationController.shared.exitToInline()
            } label: {
                BadgedGlyph(badge: "详情页", offset: CGSize(width: 9, height: -18)) {
                    CornersGlyph(inward: true)
                        .stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 16.5)
                }
            }
            .accessibilityLabel("详情页")
            .padding(.leading, 3)
            Button {
                chrome.touch()
                OrientationController.shared.enterLandscape()
            } label: {
                FullScreenGlyph()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: 15.5, height: 15.5)
                    .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("横屏全屏")
            .padding(.leading, 1)
            .padding(.trailing, 5)
        }
    }
}
