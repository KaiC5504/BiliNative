import Foundation
import Observation
import BiliAPI

/// One opening of the comment composer (14): the text for one reply target, the emote panel switch, and posting.
@MainActor
@Observable
final class ComposerModel {
    let target: ReplyTarget
    var text: String {
        didSet { comments.drafts.texts[draftKey] = text }
    }
    var syncToDynamic = false
    var showingEmotes = false
    private(set) var posting = false
    /// Read once when the composer opens, so the row does not reshuffle under the finger while emotes are tapped.
    let recent: [Emote]

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let aid: Int64
    @ObservationIgnored private let comments: CommentsModel
    @ObservationIgnored private let defaults: UserDefaults

    init(client: BiliClient, aid: Int64, target: ReplyTarget, comments: CommentsModel, defaults: UserDefaults = .standard) {
        self.client = client
        self.aid = aid
        self.target = target
        self.comments = comments
        self.defaults = defaults
        text = comments.drafts.texts[Self.draftKey(target, aid: aid)] ?? ""
        recent = RecentEmotes.list(defaults: defaults)
    }

    var placeholder: String {
        switch target {
        case .video: return "哎呦，不错哦，发条评论吧"
        case .comment(let comment): return "回复 \(comment.member.name):"
        case .threadReply(_, let reply): return "回复 \(reply.member.name):"
        }
    }

    var canPost: Bool { !trimmed.isEmpty && !posting && !comments.drafts.posting.contains(draftKey) }

    func insert(_ emote: Emote) {
        text += emote.token
        RecentEmotes.record(emote, defaults: defaults)
    }

    /// True once the comment is posted and shown; on failure the text stays and the page toasts the reason.
    func post() async -> Bool {
        guard canPost else { return false }
        let fields = postFields()
        posting = true
        comments.drafts.setPosting(draftKey, true)
        defer {
            posting = false
            comments.drafts.setPosting(draftKey, false)
        }
        do {
            let posted = try await client.postComment(aid: aid, message: fields.message, root: fields.root,
                                                      parent: fields.parent, syncToDynamic: syncToDynamic)
            comments.inserted(posted)
            text = ""
            comments.drafts.texts[draftKey] = nil
            return true
        } catch {
            comments.fail(error)
            return false
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func postFields() -> (message: String, root: Int64, parent: Int64) {
        switch target {
        case .video:
            return (trimmed, 0, 0)
        case .comment(let comment):
            return (trimmed, comment.rpid, comment.rpid)
        case .threadReply(let root, let reply):
            // The server links the reply to its parent, but the thread only shows who it answers through this prefix.
            return ("回复 @\(reply.member.name) :" + trimmed, root.rpid, reply.rpid)
        }
    }

    private var draftKey: String { Self.draftKey(target, aid: aid) }

    /// Drafts outlive a switch to another video of the page, so a comment on the video itself names the video.
    static func draftKey(_ target: ReplyTarget, aid: Int64) -> String {
        switch target {
        case .video: return "video.\(aid)"
        case .comment(let comment): return "comment.\(comment.rpid)"
        case .threadReply(_, let reply): return "reply.\(reply.rpid)"
        }
    }
}
