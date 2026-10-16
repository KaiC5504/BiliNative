import SwiftUI
import AppLogic

enum PageTab: Hashable {
    case intro, comments
}

/// The sheets that cover the page below the player (19).
enum PageSheet: Equatable {
    case collection, parts
}

/// The tab under the player, how far each tab has scrolled, and the sheet over them. The page reads the offset of
/// the shown tab to shrink the paused player.
@MainActor
@Observable
final class PageTabsState {
    var selection: PageTab = .intro
    var sheet: PageSheet?
    private(set) var offsets: [PageTab: CGFloat] = [:]
    private var positions: [PageTab: ScrollPosition] = [:]

    var offset: CGFloat { offsets[selection] ?? 0 }

    func setOffset(_ offset: CGFloat, for tab: PageTab) {
        guard offsets[tab] != offset else { return }
        offsets[tab] = offset
    }

    func positionBinding(for tab: PageTab) -> Binding<ScrollPosition> {
        Binding(get: { self.positions[tab] ?? ScrollPosition(edge: .top) },
                set: { self.positions[tab] = $0 })
    }

    func scrollToTop() {
        positions[selection, default: ScrollPosition(edge: .top)].scrollTo(edge: .top)
    }

    func scroll(_ tab: PageTab, toY y: CGFloat) {
        positions[tab, default: ScrollPosition(edge: .top)].scrollTo(y: y)
    }
}

/// 简介 and 评论 side by side; they switch by the tab row or by swiping sideways. Each tab's scroll view applies
/// `collapsingPlayerScroll(_:tab:)` so the paused player shrinks as it scrolls.
struct PageTabs<Intro: View, Comments: View>: View {
    @Bindable var state: PageTabsState
    let reserve: CGFloat
    @ViewBuilder let intro: () -> Intro
    @ViewBuilder let comments: () -> Comments

    var body: some View {
        TabView(selection: $state.selection) {
            intro()
                .tag(PageTab.intro)
            comments()
                .tag(PageTab.comments)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.playerReserve, reserve)
        .background(Theme.Page.background)
    }
}

/// 简介 / 评论 N with the pink underline, and at the right the danmaku field joined to the 弹 toggle (10, 18), or the
/// 弹 toggle alone while danmaku is off (03).
struct PageTabRow: View {
    let state: PageTabsState
    /// Nil until the video has loaded.
    let replyCount: Int64?
    let danmakuEnabled: Bool
    let danmakuClosed: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            tab(.intro, title: "简介", count: nil)
            tab(.comments, title: "评论", count: replyCount)
                .padding(.leading, 28)
            Spacer(minLength: 8)
            if danmakuEnabled {
                sendField
            } else {
                toggle
                    .frame(width: 43, height: 29)
                    .background(Theme.softGrey, in: Capsule())
                    .overlay(Capsule().stroke(Theme.divider, lineWidth: 0.7))
            }
        }
        .padding(.leading, 21)
        .padding(.trailing, Theme.Metrics.gutter)
        .frame(height: Theme.Page.tabRowHeight)
        .background(Theme.Page.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
        .animation(.snappy(duration: 0.25), value: state.selection)
    }

    private func tab(_ tab: PageTab, title: String, count: Int64?) -> some View {
        let selected = state.selection == tab
        return Button {
            state.selection = tab
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title)
                    .font(.system(size: 15))
                if let count {
                    Text(CountFormat.short(count))
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(selected ? Theme.pink : Theme.Page.tabText)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(Theme.pink)
                        .frame(height: 2.5)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sendField: some View {
        HStack(spacing: 0) {
            Button(action: onSendDanmaku) {
                Text(danmakuClosed ? "UP主已关闭弹幕" : "点我发弹幕")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(danmakuClosed)
            .background(Theme.softGrey)
            toggle
                .frame(width: 39)
                .background(Theme.Page.background)
        }
        .frame(height: 29)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.divider, lineWidth: 0.7))
    }

    private var toggle: some View {
        Button(action: onToggleDanmaku) {
            (danmakuEnabled ? BorrowedIcon.danmakuOn : BorrowedIcon.danmakuOff).image
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.Page.tabText)
                .frame(width: 22, height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(danmakuEnabled ? "关闭弹幕" : "开启弹幕")
    }
}
