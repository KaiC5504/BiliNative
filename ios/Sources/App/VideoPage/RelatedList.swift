import SwiftUI
import AppLogic
import BiliAPI

/// 相关推荐 under the 简介 (03, 18). A tap opens the video on a page of its own; ⋮ offers 稍后再看.
struct RelatedList: View {
    let cards: [VideoCard]
    let onOpen: (VideoCard) -> Void
    let onWatchLater: (VideoCard) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(cards, id: \.bvid) { card in
                RelatedRow(card: card, onOpen: { onOpen(card) }, onWatchLater: { onWatchLater(card) })
            }
        }
    }
}

private struct RelatedRow: View {
    let card: VideoCard
    let onOpen: () -> Void
    let onWatchLater: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                VideoThumb(cover: card.cover, duration: VideoThumb.shortClock(card.duration), size: Theme.Page.relatedThumb)
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.title)
                        .font(Theme.Page.bodyFont)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text("UP")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 2)
                            .frame(height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(lineWidth: 1))
                        Text(card.ownerName)
                            .font(Theme.Page.metaFont)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    VideoCounts(views: card.views, danmaku: card.danmaku)
                        .padding(.top, 4)
                        .padding(.trailing, 28)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Page.relatedThumb.height, alignment: .leading)
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button(action: onWatchLater) {
                    Label("稍后再看", systemImage: "clock")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 36, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多")
            .padding(.trailing, 4)
            .padding(.bottom, 6)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
                .padding(.leading, Theme.Metrics.gutter)
        }
    }
}

/// ▶ plays and ☰ danmaku, grey, as under every video row.
struct VideoCounts: View {
    let views: Int64
    let danmaku: Int64

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.rectangle")
            Text(CountFormat.short(views))
            Image(systemName: "list.bullet.rectangle")
                .padding(.leading, 10)
            Text(CountFormat.short(danmaku))
        }
        .font(Theme.Page.metaFont)
        .foregroundStyle(Theme.secondaryText)
        .lineLimit(1)
    }
}

/// A cover with its duration in the bottom right corner.
struct VideoThumb: View {
    let cover: String
    let duration: String
    let size: CGSize

    var body: some View {
        RemoteImage(cover)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomTrailing) {
                Text(duration)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(height: 18)
                    .background(Theme.Page.durationFill, in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
    }

    /// Related rows say 2:55 where the 合集 list says 02:55.
    static func shortClock(_ seconds: Int) -> String {
        let clock = TimeFormat.clock(Double(seconds))
        return clock.count == 5 && clock.hasPrefix("0") ? String(clock.dropFirst()) : clock
    }
}
