import SwiftUI

/// The small player's height while the page scrolls (11, 12). Paused, it gives up whatever the tab content has
/// scrolled, down to a bar; playing, it keeps its 16:9 height.
struct CollapsingPlayer {
    static let barHeight: CGFloat = 56

    let fullHeight: CGFloat

    /// What each tab's content leaves free above itself, so it starts under the full-height player.
    var reserve: CGFloat { max(0, fullHeight - Self.barHeight) }

    func height(forOffset offset: CGFloat, paused: Bool) -> CGFloat {
        guard paused else { return fullHeight }
        return min(fullHeight, max(Self.barHeight, fullHeight - max(0, offset)))
    }

    /// 0 at full height, 1 once it is the bar.
    func progress(height: CGFloat) -> CGFloat {
        guard reserve > 0 else { return 0 }
        return min(1, max(0, (fullHeight - height) / reserve))
    }
}

/// Over the shrinking player: the video darkens and "▶ 继续播放" fades in; collapsed, back and ⋮ join it (12).
/// Any tap on it resumes, as the bar in the official app does.
struct CollapsedPlayerBar: View {
    let progress: CGFloat
    let onResume: () -> Void
    let onBack: () -> Void
    let onMore: () -> Void

    var body: some View {
        ZStack {
            Theme.Page.collapsedShade
                .opacity(progress)
            Button(action: onResume) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17))
                    Text("继续播放")
                        .font(.system(size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(Double(min(1, progress * 1.6)))
            .accessibilityLabel("继续播放")
            if progress >= 1 {
                HStack(spacing: 0) {
                    ChromeButton(systemName: "chevron.left", label: "返回", action: onBack)
                    Spacer(minLength: 0)
                    MoreButton(action: onMore)
                }
                .padding(.horizontal, 1)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: progress >= 1)
    }
}

private struct PlayerReserveKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Set by the page on its tabs: the room each tab's scroll view leaves above its content for the player.
    var playerReserve: CGFloat {
        get { self[PlayerReserveKey.self] }
        set { self[PlayerReserveKey.self] = newValue }
    }
}

private struct CollapsingScroll: ViewModifier {
    let state: PageTabsState
    let tab: PageTab
    @Environment(\.playerReserve) private var reserve

    func body(content: Content) -> some View {
        content
            .scrollPosition(state.positionBinding(for: tab))
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                state.setOffset(offset, for: tab)
            }
            // A safe-area inset rather than a content margin: the scroll geometry's insets always include it.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: reserve)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// For each tab's scroll view: it starts under the full-height player, and its offset shrinks the paused player.
    func collapsingPlayerScroll(_ state: PageTabsState, tab: PageTab) -> some View {
        modifier(CollapsingScroll(state: state, tab: tab))
    }
}
