import Foundation
import Observation
import BiliAPI
import DevLog

/// Where a tap that writes asks the composer (Task 25) to post.
enum ReplyTarget: Equatable {
    case video
    case comment(Comment)
    case threadReply(root: Comment, reply: Comment)
}

/// The pictures of one comment open full screen, starting at `index`.
struct PictureViewing: Equatable {
    var pictures: [CommentPicture]
    var index: Int
}

/// The composer's unsent text per reply target (`ComposerModel.draftKey`), and the targets being posted to. The page
/// keeps one for as long as it lives and hands it to the comments of every video it switches to.
@MainActor
@Observable
final class CommentDrafts {
    @ObservationIgnored var texts: [String: String] = [:]
    /// A composer closed while posting must not let a reopened one post the same text again.
    private(set) var posting: Set<String> = []

    func setPosting(_ key: String, _ on: Bool) {
        if on { posting.insert(key) } else { posting.remove(key) }
    }
}

/// The 评论 tab: the list with its sort and paging, the open reply thread, and the reactions on both.
@MainActor
@Observable
final class CommentsModel {
    struct ThreadState: Equatable {
        var root: Comment
        var replies: [Comment] = []
        var sort: CommentSort = .time
        /// The last page loaded; 0 before the first.
        var page = 0
        var isEnd = false
        var total: Int
        var loading = false
        var error: String?
    }

    /// The server's codes for a comment section that is switched off; its message replaces the list.
    private static let closedCodes: Set<Int> = [12002, 12061]

    let aid: Int64
    let upMid: Int64
    private(set) var sort: CommentSort = .hot
    private(set) var comments: [Comment] = []
    private(set) var pinned: Comment?
    private(set) var total = 0
    private(set) var isEnd = false
    private(set) var closedMessage: String?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var thread: ThreadState?
    /// Set by a failed reaction or delete; the page shows it as a toast and clears it.
    var toast: String?
    var viewing: PictureViewing?
    @ObservationIgnored let drafts: CommentDrafts

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let isLoggedIn: () -> Bool
    @ObservationIgnored private let requestLogin: () -> Void
    @ObservationIgnored private let ownMid: () -> Int64?
    @ObservationIgnored private var nextOffset: String?
    /// Bumped by every reset, so an answer for the old sort or an old thread is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var threadGeneration = 0

    init(client: BiliClient, aid: Int64, upMid: Int64, isLoggedIn: @escaping () -> Bool, requestLogin: @escaping () -> Void,
         ownMid: @escaping () -> Int64? = { nil }, drafts: CommentDrafts? = nil) {
        self.client = client
        self.drafts = drafts ?? CommentDrafts()
        self.aid = aid
        self.upMid = upMid
        self.isLoggedIn = isLoggedIn
        self.requestLogin = requestLogin
        self.ownMid = ownMid
    }

    var hasLoaded: Bool { !comments.isEmpty || pinned != nil || isEnd || closedMessage != nil || error != nil }

    func isOwn(_ comment: Comment) -> Bool {
        guard let mid = ownMid() else { return false }
        return comment.mid == mid || comment.member.mid == mid
    }

    // MARK: list

    func loadMore() async {
        guard !isEnd, !loading, closedMessage == nil else { return }
        let started = generation
        let first = nextOffset == nil && comments.isEmpty
        loading = true
        error = nil
        do {
            let page = try await client.comments(aid: aid, sort: sort, offset: nextOffset)
            guard started == generation else { return }
            loading = false
            if first {
                pinned = page.pinned
                total = page.total
            }
            var seen = Set(comments.map(\.rpid))
            if let pinned { seen.insert(pinned.rpid) }
            comments += page.comments.filter { seen.insert($0.rpid).inserted }
            nextOffset = page.nextOffset
            isEnd = page.isEnd
        } catch {
            guard started == generation else { return }
            loading = false
            if case .api(let code, let message)? = error as? BiliError, Self.closedCodes.contains(code) {
                closedMessage = message.isEmpty ? "评论区已关闭" : message
            } else if !(error is CancellationError) {
                Logger.shared.warn(.api, "comments failed", ["error": .init(String(describing: error))])
                self.error = Self.message(for: error)
            }
        }
    }

    func setSort(_ sort: CommentSort) async {
        self.sort = sort
        resetList()
        await loadMore()
    }

    /// Pull to refresh and 重试 after a first page that failed.
    func reload() async {
        resetList()
        await loadMore()
    }

    private func resetList() {
        generation += 1
        comments = []
        pinned = nil
        total = 0
        nextOffset = nil
        isEnd = false
        closedMessage = nil
        loading = false
        error = nil
    }

    /// A comment the composer posted: top-level ones go to the top of the list, replies to the top of their thread.
    func inserted(_ comment: Comment) {
        guard comment.root != 0 else {
            comments.insert(comment, at: 0)
            total += 1
            return
        }
        if thread?.root.rpid == comment.root {
            thread?.replies.insert(comment, at: 0)
            thread?.total += 1
        }
        // Also the thread's own copy of the root.
        update(comment.root) { root in
            root.replyCount += 1
            root.previewReplies.insert(comment, at: 0)
        }
    }

    // MARK: reactions

    func toggleLike(_ comment: Comment) async {
        guard let before = current(comment.rpid), loginChecked() else { return }
        let on = before.action != 1
        update(comment.rpid) { target in
            if on {
                target.likes += 1
                target.action = 1
            } else {
                target.likes = max(0, target.likes - 1)
                target.action = 0
            }
        }
        await send(rollingBack: before) { try await $0.likeComment(aid: self.aid, rpid: comment.rpid, on: on) }
    }

    func toggleHate(_ comment: Comment) async {
        guard let before = current(comment.rpid), loginChecked() else { return }
        let on = before.action != 2
        update(comment.rpid) { target in
            if on, target.action == 1 { target.likes = max(0, target.likes - 1) }
            target.action = on ? 2 : 0
        }
        await send(rollingBack: before) { try await $0.hateComment(aid: self.aid, rpid: comment.rpid, on: on) }
    }

    /// Removes the row only once the server agrees; the view confirms first.
    func delete(_ comment: Comment) async {
        guard loginChecked() else { return }
        do {
            try await client.deleteComment(aid: aid, rpid: comment.rpid)
        } catch {
            fail(error)
            return
        }
        if thread?.root.rpid == comment.rpid { closeThread() }
        let before = comments.count + (pinned == nil ? 0 : 1)
        if pinned?.rpid == comment.rpid { pinned = nil }
        comments.removeAll { $0.rpid == comment.rpid }
        if comments.count + (pinned == nil ? 0 : 1) < before { total = max(0, total - 1) }
        if thread != nil, let index = thread?.replies.firstIndex(where: { $0.rpid == comment.rpid }) {
            thread?.replies.remove(at: index)
            // Read first: an optional-chained write holds `thread` while its right side runs.
            let total = thread?.total ?? 1
            thread?.total = max(0, total - 1)
        }
        if comment.root != 0 {
            update(comment.root) { root in
                root.replyCount = max(0, root.replyCount - 1)
                root.previewReplies.removeAll { $0.rpid == comment.rpid }
            }
        }
    }

    private func loginChecked() -> Bool {
        guard isLoggedIn() else {
            requestLogin()
            return false
        }
        return true
    }

    private func send(rollingBack before: Comment, _ call: (BiliClient) async throws -> Void) async {
        do {
            try await call(client)
        } catch {
            update(before.rpid) { target in
                target.likes = before.likes
                target.action = before.action
            }
            fail(error)
        }
    }

    /// Also the composer's: the server's words as a toast, and the login screen when the session is gone.
    func fail(_ error: Error) {
        guard !(error is CancellationError) else { return }
        Logger.shared.warn(.api, "comment action failed", ["error": .init(String(describing: error))])
        if (error as? BiliError)?.needsLogin == true { requestLogin() }
        toast = Self.message(for: error)
    }

    /// Bilibili words its refusals for the user (too frequent, already deleted); those are shown as sent.
    private static func message(for error: Error) -> String {
        guard let error = error as? BiliError else { return "网络连接失败，请稍后再试" }
        if case .api(let code, let message) = error, !message.isEmpty, code > 0 { return message }
        return error.userMessage
    }

    /// The comment as shown now, wherever it is: the same rpid can be in the list, a preview and the thread.
    private func current(_ rpid: Int64) -> Comment? {
        if let root = thread?.root, root.rpid == rpid { return root }
        if let reply = thread?.replies.first(where: { $0.rpid == rpid }) { return reply }
        if let pinned, pinned.rpid == rpid { return pinned }
        for comment in comments {
            if comment.rpid == rpid { return comment }
            if let reply = comment.previewReplies.first(where: { $0.rpid == rpid }) { return reply }
        }
        return nil
    }

    private func update(_ rpid: Int64, _ change: (inout Comment) -> Void) {
        func apply(_ comment: inout Comment) {
            if comment.rpid == rpid { change(&comment) }
            for index in comment.previewReplies.indices where comment.previewReplies[index].rpid == rpid {
                change(&comment.previewReplies[index])
            }
        }
        for index in comments.indices { apply(&comments[index]) }
        if pinned != nil { apply(&pinned!) }
        if thread != nil {
            apply(&thread!.root)
            for index in thread!.replies.indices { apply(&thread!.replies[index]) }
        }
    }

    // MARK: thread

    func openThread(_ root: Comment) async {
        threadGeneration += 1
        thread = ThreadState(root: root, total: root.replyCount)
        await loadMoreThread()
    }

    func closeThread() {
        threadGeneration += 1
        thread = nil
    }

    func setThreadSort(_ sort: CommentSort) async {
        guard let root = thread?.root else { return }
        threadGeneration += 1
        thread = ThreadState(root: root, sort: sort, total: thread?.total ?? root.replyCount)
        await loadMoreThread()
    }

    func loadMoreThread() async {
        guard let state = thread, !state.isEnd, !state.loading else { return }
        let started = threadGeneration
        thread?.loading = true
        thread?.error = nil
        do {
            let page = try await client.thread(aid: aid, root: state.root.rpid, page: state.page + 1, sort: state.sort)
            guard started == threadGeneration, thread != nil else { return }
            var seen = Set(thread!.replies.map(\.rpid))
            thread!.replies += page.replies.filter { seen.insert($0.rpid).inserted }
            thread!.page = state.page + 1
            thread!.total = page.total
            thread!.isEnd = page.isEnd
            thread!.loading = false
            if state.page == 0 {
                // The thread's own copy is fresher, but the list's knows it is pinned.
                var root = page.root
                root.isPinned = state.root.isPinned
                thread!.root = root
            }
        } catch {
            guard started == threadGeneration, thread != nil else { return }
            thread!.loading = false
            if !(error is CancellationError) {
                Logger.shared.warn(.api, "comment thread failed", ["error": .init(String(describing: error))])
                thread!.error = Self.message(for: error)
            }
        }
    }
}
