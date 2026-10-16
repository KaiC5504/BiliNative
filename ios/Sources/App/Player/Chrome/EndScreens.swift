import SwiftUI
import AppLogic
import BiliAPI

enum ShareLinks {
    static func video(_ bvid: String) -> URL {
        URL(string: "https://www.bilibili.com/video/\(bvid)") ?? URL(string: "https://www.bilibili.com")!
    }
}

/// The end of a video in the small player (26): 推荐视频 with the first related video, 立即播放, 重播 and 分享.
struct EndScreenPortrait: View {
    let model: VideoPageModel
    @Binding var panel: PlayerPanel?
    let onBack: () -> Void
    let onOpen: (VideoCard) -> Void

    var body: some View {
        ZStack {
            Theme.Chrome.endDim
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ChromeButton(systemName: "chevron.left", label: "返回", action: onBack)
                    Spacer(minLength: 0)
                    MoreButton { panel = .more }
                }
                .padding(.horizontal, 1)
                .padding(.top, 1)
                Spacer(minLength: 0)
                if let card = model.related.first {
                    Text("推荐视频")
                        .font(Theme.Chrome.smallFont)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.leading, 12)
                    HStack(alignment: .bottom, spacing: 11) {
                        Button { onOpen(card) } label: {
                            Cover(card: card, showsCounts: false)
                                .frame(width: 128, height: 72)
                                .overlay {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.white.opacity(0.95))
                                }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(card.title)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            UploaderLine(name: card.ownerName)
                            CountsLine(views: card.views, danmaku: card.danmaku)
                                .padding(.top, 4)
                        }
                        .frame(height: 72)
                        Spacer(minLength: 8)
                        Button { onOpen(card) } label: {
                            Text("立即播放")
                                .font(Theme.Chrome.labelFont)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 29)
                                .background(Theme.Chrome.endButton, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Button { Task { await model.replay() } } label: {
                        Label { Text("重播") } icon: { Image(systemName: "arrow.clockwise") }
                            .labelStyle(EndActionLabelStyle())
                    }
                    if let bvid = model.detail?.bvid {
                        ShareLink(item: ShareLinks.video(bvid)) {
                            Label { Text("分享") } icon: { Image(systemName: "arrowshape.turn.up.right") }
                                .labelStyle(EndActionLabelStyle())
                        }
                        .padding(.leading, 12)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: Theme.Chrome.button)
                .padding(.leading, 12)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The end of a video in landscape (27): the uploader, 重播 | 点赞 投币 收藏 分享, and a row of related videos.
struct EndScreenLandscape: View {
    let model: VideoPageModel
    let insets: EdgeInsets
    let showsActions: Bool
    let onBack: () -> Void
    let onOpen: (VideoCard) -> Void

    var body: some View {
        ZStack {
            Theme.Chrome.endDim
            VStack(alignment: .leading, spacing: 0) {
                ChromeButton(systemName: "chevron.left", label: "返回", action: onBack)
                    .frame(height: 40)
                    .padding(.leading, insets.leading - 1)
                    .padding(.top, 2)
                rule
                uploaderRow
                    .frame(height: 96)
                rule
                Text("推荐视频")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .padding(.leading, insets.leading + 13)
                    .padding(.top, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 13) {
                        ForEach(model.related, id: \.bvid) { card in
                            Button { onOpen(card) } label: { RelatedCard(card: card) }
                        }
                    }
                    .padding(.horizontal, 13)
                }
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
                .padding(.top, 12)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.Chrome.divider)
            .frame(height: 0.5)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
    }

    private var uploaderRow: some View {
        HStack(spacing: 0) {
            if let owner = model.detail?.owner {
                RemoteImage(owner.face)
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                VStack(alignment: .leading, spacing: 11) {
                    Text(owner.name)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if showsActions {
                        Text("+ 关注")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 88, height: 29)
                            .background(Theme.pink, in: Capsule())
                    }
                }
                .padding(.leading, 14)
            }
            Spacer(minLength: 16)
            endAction("重播", systemName: "arrow.clockwise") { Task { await model.replay() } }
            Rectangle()
                .fill(Theme.Chrome.divider)
                .frame(width: 0.5, height: 60)
                .padding(.horizontal, 20)
            if showsActions {
                endAction("点赞", systemName: "hand.thumbsup") {}
                endAction("投币", coin: true) {}
                endAction("收藏", systemName: "star") {}
            }
            if let bvid = model.detail?.bvid {
                ShareLink(item: ShareLinks.video(bvid)) {
                    EndActionCell(title: "分享", systemName: "arrowshape.turn.up.right")
                }
            }
        }
        .padding(.leading, insets.leading + 13)
        .padding(.trailing, insets.trailing)
    }

    private func endAction(_ title: String, systemName: String = "", coin: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            EndActionCell(title: title, systemName: systemName, coin: coin)
        }
    }
}

private struct EndActionCell: View {
    let title: String
    var systemName = ""
    var coin = false

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if coin {
                    CoinGlyph(filled: false).frame(width: 21, height: 21)
                } else {
                    Image(systemName: systemName).font(.system(size: 21))
                }
            }
            .frame(height: 22)
            Text(title)
                .font(.system(size: 14))
        }
        .foregroundStyle(.white)
        .frame(width: 58)
        .contentShape(Rectangle())
    }
}

private struct EndActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon
                .font(.system(size: 20))
            configuration.title
                .font(.system(size: 16))
        }
        .foregroundStyle(.white)
        .frame(height: Theme.Chrome.button)
        .contentShape(Rectangle())
    }
}

/// A related video's cover with its counts and duration on it, as in 27's row.
private struct RelatedCard: View {
    let card: VideoCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Cover(card: card, showsCounts: true)
                .frame(width: 201, height: 113)
            Text(card.title)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 201, alignment: .leading)
                .padding(.top, 7)
            UploaderLine(name: card.ownerName)
                .padding(.top, 5)
        }
        .frame(width: 201, alignment: .topLeading)
    }
}

private struct Cover: View {
    let card: VideoCard
    let showsCounts: Bool

    var body: some View {
        RemoteImage(card.cover)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 30)
                    HStack(spacing: 0) {
                        if showsCounts {
                            CountsLine(views: card.views, danmaku: card.danmaku)
                        }
                        Spacer(minLength: 4)
                        Text(TimeFormat.clock(Double(card.duration)).trimmingLeadingZero)
                            .font(.system(size: 12).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct UploaderLine: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Text("UP")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 2)
                .frame(height: 12)
                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(lineWidth: 1))
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}

private struct CountsLine: View {
    let views: Int64
    let danmaku: Int64

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.rectangle")
            Text(CountFormat.short(views))
            Image(systemName: "list.bullet.rectangle")
                .padding(.leading, 8)
            Text(CountFormat.short(danmaku))
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
    }
}

private extension String {
    /// Covers say 0:48, not 00:48.
    var trimmingLeadingZero: String {
        count == 5 && hasPrefix("0") ? String(dropFirst()) : self
    }
}
