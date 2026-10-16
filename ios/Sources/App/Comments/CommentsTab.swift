import SwiftUI
import BiliAPI

/// The 评论 tab (10): 热门评论 or 最新评论 with the sort switch, the pinned comment, the list with endless scroll,
/// and the fixed bar that opens the composer. A closed section shows the server's message instead of the list.
struct CommentsTab: View {
    let model: CommentsModel
    let tabs: PageTabsState
    /// Task 25's composer: what to reply to, and whether to open on the emote panel.
    let onCompose: (ReplyTarget, Bool) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let closed = model.closedMessage {
                    ClosedNotice(message: closed)
                } else {
                    SortHeader(title: model.sort == .hot ? "热门评论" : "最新评论", sort: model.sort) { sort in
                        Task { await model.setSort(sort) }
                    }
                    if let pinned = model.pinned {
                        row(pinned)
                    }
                    ForEach(model.comments) { comment in
                        row(comment)
                    }
                    ListFooter(loading: model.loading, error: model.error, isEnd: model.isEnd,
                               isEmpty: model.comments.isEmpty && model.pinned == nil,
                               onMore: { Task { await model.loadMore() } })
                }
            }
        }
        .scrollIndicators(.hidden)
        .collapsingPlayerScroll(tabs, tab: .comments)
        // The tabs reach under the home indicator, so the bar keeps clear of it itself.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CommentBar(bottomInset: ScreenInsets.current(merging: EdgeInsets()).bottom) { emotes in onCompose(.video, emotes) }
        }
        .background(Theme.Comments.background)
        .task {
            if !model.hasLoaded { await model.loadMore() }
        }
    }

    private func row(_ comment: Comment) -> some View {
        CommentRow(comment: comment, model: model,
                   onReply: { onCompose(.comment($0), false) },
                   onOpenThread: { root in Task { await model.openThread(root) } })
    }
}

/// "热门评论 … ☰ 按热度" in the list, "相关回复共N条 … ☰ 按时间" in a thread.
struct SortHeader: View {
    let title: String
    let sort: CommentSort
    let onChange: (CommentSort) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
            Spacer(minLength: 8)
            Button {
                onChange(sort == .hot ? .time : .hot)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .light))
                    Text(sort == .hot ? "按热度" : "按时间")
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("切换排序")
        }
        .font(Theme.Comments.headerFont)
        .foregroundStyle(Theme.Comments.header)
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.top, 9)
        .frame(height: Theme.Comments.headerHeight, alignment: .top)
    }
}

/// The end of a list: a spinner that asks for more as it scrolls in, "没有更多了", or a retry row.
struct ListFooter: View {
    let loading: Bool
    let error: String?
    let isEnd: Bool
    let isEmpty: Bool
    let onMore: () -> Void

    var body: some View {
        Group {
            if let error {
                Button(action: onMore) {
                    VStack(spacing: 6) {
                        Text(error)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                        Text("点击重试")
                            .foregroundStyle(Theme.link)
                    }
                    .font(Theme.Comments.metaFont)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if isEnd {
                Text(isEmpty ? "还没有评论，快来抢沙发吧" : "没有更多了")
                    .font(Theme.Comments.metaFont)
                    .foregroundStyle(Theme.Comments.meta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isEmpty ? 48 : 20)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isEmpty ? 48 : 20)
                    .onAppear { if !loading { onMore() } }
            }
        }
    }
}

private struct ClosedNotice: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34, weight: .light))
            Text(message)
                .font(Theme.Comments.fieldFont)
        }
        .foregroundStyle(Theme.Comments.header)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// The fixed bar under the list and the thread: "哎呦，不错哦，发条评论吧" and the emote button (10).
struct CommentBar: View {
    /// Room for the home indicator when the bar's container ignores the safe area.
    var bottomInset: CGFloat = 0
    /// True when the emote button was tapped.
    let onWrite: (Bool) -> Void

    private typealias T = Theme.Comments

    var body: some View {
        HStack(spacing: 3) {
            Button {
                onWrite(false)
            } label: {
                Text("哎呦，不错哦，发条评论吧")
                    .font(T.fieldFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: T.fieldHeight)
                    .background(T.field, in: Capsule())
                    .contentShape(Capsule())
            }
            Button {
                onWrite(true)
            } label: {
                EmoteFace()
                    .stroke(Theme.secondaryText, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
                    .frame(width: 44, height: T.fieldHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("表情")
        }
        .buttonStyle(.plain)
        .padding(.leading, Theme.Metrics.gutter)
        .padding(.top, T.barTop)
        .padding(.bottom, T.barTop + bottomInset)
        .background(T.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
    }
}

/// The emote button's face: a circle with ">  <" eyes and an ω mouth (10).
struct EmoteFace: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = side / 20
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }
        var path = Path(ellipseIn: CGRect(x: origin.x + 0.7 * unit, y: origin.y + 0.7 * unit, width: side - 1.4 * unit, height: side - 1.4 * unit))
        path.move(to: point(5.6, 6.9))
        path.addLine(to: point(8.0, 8.4))
        path.addLine(to: point(5.6, 9.9))
        path.move(to: point(14.4, 6.9))
        path.addLine(to: point(12.0, 8.4))
        path.addLine(to: point(14.4, 9.9))
        path.move(to: point(6.6, 12.2))
        path.addQuadCurve(to: point(10, 12.6), control: point(8.2, 15.6))
        path.addQuadCurve(to: point(13.4, 12.2), control: point(11.8, 15.6))
        return path
    }
}
