import SwiftUI
import BiliAPI

/// 评论详情 (13): over the tabs under the player, the root comment in full, a grey band, "相关回复共N条" with its sort,
/// then the replies. ✕ goes back to the list.
struct ThreadView: View {
    @Bindable var model: CommentsModel
    let thread: CommentsModel.ThreadState
    /// Task 25's composer: what to reply to, and whether to open on the emote panel.
    let onCompose: (ReplyTarget, Bool) -> Void

    private typealias T = Theme.Comments

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    CommentRow(comment: thread.root, model: model, showsReplies: false, showsDivider: false,
                               onReply: { onCompose(.comment($0), false) })
                    T.band
                        .frame(height: T.bandHeight)
                        .padding(.top, 1)
                    SortHeader(title: "相关回复共\(thread.total)条", sort: thread.sort) { sort in
                        Task { await model.setThreadSort(sort) }
                    }
                    ForEach(thread.replies) { reply in
                        CommentRow(comment: reply, model: model, showsReplies: false,
                                   onReply: { onCompose(.threadReply(root: thread.root, reply: $0), false) })
                    }
                    ListFooter(loading: thread.loading, error: thread.error, isEnd: thread.isEnd, isEmpty: thread.replies.isEmpty,
                               onMore: { Task { await model.loadMoreThread() } })
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CommentBar { emotes in onCompose(.comment(thread.root), emotes) }
            }
        }
        .background(T.background)
        .toast($model.toast)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("评论详情")
                .font(T.titleFont)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Button {
                model.closeThread()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(T.header)
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.leading, Theme.Metrics.gutter)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(T.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
    }
}
