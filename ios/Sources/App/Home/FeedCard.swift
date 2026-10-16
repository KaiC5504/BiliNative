import SwiftUI
import AppLogic
import BiliAPI

/// Sizes measured on 01 (iPhone 17 Pro Max, 3 px per point).
enum FeedMetrics {
    static let spacing: CGFloat = 6
    /// 633 × 475 px in 01, so 4:3 rather than the 16:10 the spec guessed.
    static let coverAspect: CGFloat = 4 / 3
    static let inset: CGFloat = 8
    static let titleSize: CGFloat = 14
    static let footerSize: CGFloat = 12
    static let tagSize: CGFloat = 11
    static let tagHeight: CGFloat = 16
    static let statSize: CGFloat = 11
    static let statIconSize: CGFloat = 13
}

/// One 推荐 card (01): cover with counts and duration, a two-line title, and the tag, uploader and ⋮ footer.
struct FeedCardView: View {
    let card: FeedCard
    let onOpen: () -> Void
    let onWatchLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            Text(card.title)
                .font(.system(size: FeedMetrics.titleSize))
                .foregroundStyle(Theme.text)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, FeedMetrics.inset)
                .padding(.top, 10)
            footer
                .padding(.top, 9)
                .padding(.bottom, 9)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(FeedMetrics.coverAspect, contentMode: .fit)
            .overlay { RemoteImage(card.cover) }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Theme.coverShade], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
            }
            .overlay(alignment: .bottom) { stats }
            .clipped()
    }

    private var stats: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.rectangle")
                .font(.system(size: FeedMetrics.statIconSize))
            Text(CountFormat.short(card.views))
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: FeedMetrics.statIconSize))
                .padding(.leading, 10)
            Text(CountFormat.short(card.danmaku))
            Spacer(minLength: 4)
            // On a narrow phone the counts give way; the duration is never cut.
            Text(Self.duration(card.duration))
                .fixedSize()
                .layoutPriority(1)
        }
        .font(.system(size: FeedMetrics.statSize))
        .monospacedDigit()
        .foregroundStyle(Theme.onCover)
        .lineLimit(1)
        .padding(.horizontal, FeedMetrics.inset)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            badge
            Text(card.ownerName)
                .font(.system(size: FeedMetrics.footerSize))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button("稍后再看", systemImage: "clock", action: onWatchLater)
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: FeedMetrics.footerSize, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 24, height: FeedMetrics.tagHeight + 8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多")
        }
        .frame(height: FeedMetrics.tagHeight)
        .padding(.leading, FeedMetrics.inset)
    }

    @ViewBuilder
    private var badge: some View {
        if let reason = card.reason, !reason.isEmpty {
            Tag(text: reason)
        } else if card.isVertical {
            Tag(text: "竖屏")
        } else {
            UPBadge()
        }
    }

    /// Covers say 0:18, not 00:18 (01).
    static func duration(_ seconds: Int) -> String {
        let clock = TimeFormat.clock(Double(seconds))
        return clock.hasPrefix("0") && clock.count == 5 ? String(clock.dropFirst()) : clock
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: FeedMetrics.tagSize))
            .foregroundStyle(Theme.reason)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(height: FeedMetrics.tagHeight)
            .background(Theme.reasonTint, in: RoundedRectangle(cornerRadius: 2))
            .fixedSize()
    }
}

struct UPBadge: View {
    var body: some View {
        Text("UP")
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 2)
            .frame(height: 12)
            .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(lineWidth: 1))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }
}
