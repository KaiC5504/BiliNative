import Foundation

private extension KeyedDecodingContainer where K == AnyKey {
    func text(_ key: String) -> String? {
        try? decodeIfPresent(String.self, forKey: AnyKey(key))
    }

    /// The API mixes true/false and 0/1 for flags, sometimes within one response.
    func flag(_ key: String) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: AnyKey(key)) { return value }
        return count(key) != 0
    }

    /// A malformed value costs that entry, not the dictionary.
    func table<T: Decodable>(_ key: String, of type: T.Type) -> [String: T] {
        guard let entries = try? decodeIfPresent([String: Lossy<T>].self, forKey: AnyKey(key)) else { return [:] }
        return entries.compactMapValues(\.value)
    }
}

public enum CommentSort: Int, Sendable {
    /// The value is the `mode` of the cursor endpoint; the reply-thread endpoint uses `threadSort` instead.
    case hot = 3
    case time = 2

    var threadSort: Int { self == .hot ? 1 : 0 }
}

public struct CommentMember: Sendable, Equatable {
    public var mid: Int64
    public var name: String
    public var face: String
    public var level: Int
    public var isVip: Bool
    public var pendant: String?
    public var fanCardImage: String?
    public var fanCardNumber: String?
    /// The number's colour as the server writes it, such as "#f35543".
    public var fanCardColor: String?

    public init(mid: Int64, name: String = "", face: String = "", level: Int = 0, isVip: Bool = false,
                pendant: String? = nil, fanCardImage: String? = nil, fanCardNumber: String? = nil, fanCardColor: String? = nil) {
        self.mid = mid
        self.name = name
        self.face = face
        self.level = level
        self.isVip = isVip
        self.pendant = pendant
        self.fanCardImage = fanCardImage
        self.fanCardNumber = fanCardNumber
        self.fanCardColor = fanCardColor
    }
}

extension CommentMember: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        // The member's own mid is a string here, unlike the number on the comment.
        mid = container.count("mid")
        name = container.text("uname") ?? ""
        face = container.text("avatar") ?? ""
        level = Int(container.nested("level_info")?.count("current_level") ?? 0)
        isVip = container.nested("vip")?.count("vipStatus") == 1
        pendant = container.nested("pendant")?.text("image").flatMap { $0.isEmpty ? nil : $0 }
        let card = container.nested("user_sailing")?.nested("cardbg")
        fanCardImage = card?.text("image").flatMap { $0.isEmpty ? nil : $0 }
        fanCardNumber = card?.nested("fan")?.text("num_desc").flatMap { $0.isEmpty ? nil : $0 }
        fanCardColor = card?.nested("fan")?.text("color").flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct CommentPicture: Sendable, Equatable {
    public var url: String
    public var width: Double
    public var height: Double

    public init(url: String, width: Double, height: Double) {
        self.url = url
        self.width = width
        self.height = height
    }
}

extension CommentPicture: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let url = container.text("img_src"), !url.isEmpty else { throw missing("img_src", decoder) }
        self.url = url
        width = (try? container.first(Double.self, "img_width")) ?? 0
        height = (try? container.first(Double.self, "img_height")) ?? 0
    }
}

public struct Comment: Identifiable, Sendable, Equatable {
    public let rpid: Int64
    public let oid: Int64
    public let mid: Int64
    public let root: Int64
    public let parent: Int64
    public let ctime: Int64
    public var likes: Int64
    public var replyCount: Int
    /// The viewer's own reaction: 0 none, 1 liked, 2 disliked.
    public var action: Int
    public let member: CommentMember
    public let message: String
    public let runs: [RichRun]
    public let pictures: [CommentPicture]
    public let location: String?
    public let upLiked: Bool
    public var isPinned: Bool
    public var previewReplies: [Comment]

    public var id: Int64 { rpid }

    /// `runs` defaults to the message as plain text, for fixtures and freshly typed comments.
    public init(rpid: Int64, oid: Int64 = 0, mid: Int64 = 0, root: Int64 = 0, parent: Int64 = 0, ctime: Int64 = 0,
                likes: Int64 = 0, replyCount: Int = 0, action: Int = 0, member: CommentMember, message: String,
                runs: [RichRun]? = nil, pictures: [CommentPicture] = [], location: String? = nil, upLiked: Bool = false,
                isPinned: Bool = false, previewReplies: [Comment] = []) {
        self.rpid = rpid
        self.oid = oid
        self.mid = mid
        self.root = root
        self.parent = parent
        self.ctime = ctime
        self.likes = likes
        self.replyCount = replyCount
        self.action = action
        self.member = member
        self.message = message
        self.runs = runs ?? (message.isEmpty ? [] : [.text(message)])
        self.pictures = pictures
        self.location = location
        self.upLiked = upLiked
        self.isPinned = isPinned
        self.previewReplies = previewReplies
    }
}

private struct EmoteEntry: Decodable {
    let url: String
    let size: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        url = container.text("url") ?? ""
        size = max(Int(container.nested("meta")?.count("size") ?? 1), 1)
    }
}

private struct JumpEntry: Decodable {
    let title: String
    let pcURL: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        title = container.text("title") ?? ""
        pcURL = container.text("pc_url") ?? ""
    }
}

extension Comment: Decodable {
    private static let locationPrefix = "IP属地："

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let rpid = container.count("rpid")
        guard rpid != 0 else { throw missing("rpid", decoder) }
        let mid = container.count("mid")
        let member = (try? container.first(CommentMember.self, "member")) ?? CommentMember(mid: mid)

        var message = ""
        var emotes: [String: EmoteRef] = [:]
        var mentions: [String: Int64] = [:]
        var links: [String: LinkRef] = [:]
        var pictures: [CommentPicture] = []
        if let content = container.nested("content") {
            message = content.text("message") ?? ""
            emotes = content.table("emote", of: EmoteEntry.self).mapValues { EmoteRef(url: $0.url, size: $0.size) }
            mentions = content.table("at_name_to_mid", of: Int64.self)
            for (key, entry) in content.table("jump_url", of: JumpEntry.self) {
                links[key] = LinkRef(title: entry.title.isEmpty ? key : entry.title, url: Self.absolute(entry.pcURL, orElse: key))
            }
            pictures = (try? content.first([Lossy<CommentPicture>].self, "pictures"))?.compactMap(\.value) ?? []
        }
        // A reply's "@name" is the name the target had when it was written; at_name_to_mid holds the current one.
        if let target = container.nested("parent_reply_member")?.text("name"), mentions[target] == nil,
           message.contains("@" + target) {
            let unmatched = mentions.filter { !message.contains("@" + $0.key) }
            if unmatched.count == 1, let renamed = unmatched.first {
                mentions[target] = renamed.value
            }
        }

        self.rpid = rpid
        oid = container.count("oid")
        self.mid = mid
        root = container.count("root")
        parent = container.count("parent")
        ctime = container.count("ctime")
        likes = container.count("like")
        replyCount = Int(container.count("rcount", "count"))
        action = Int(container.count("action"))
        self.member = member
        self.message = message
        runs = RichText.runs(message, emotes: emotes, mentions: mentions, links: links)
        self.pictures = pictures
        location = container.nested("reply_control")?.text("location").flatMap { text in
            let place = text.hasPrefix(Self.locationPrefix) ? String(text.dropFirst(Self.locationPrefix.count)) : text
            return place.isEmpty ? nil : place
        }
        upLiked = container.nested("up_action")?.flag("like") ?? false
        isPinned = false
        previewReplies = (try? container.first([Lossy<Comment>].self, "replies"))?.compactMap(\.value) ?? []
    }

    /// Jump links come protocol-relative ("//search.bilibili.com/..."); a word with no link at all is shown as is.
    private static func absolute(_ url: String, orElse fallback: String) -> String {
        if url.isEmpty { return fallback }
        return url.hasPrefix("//") ? "https:" + url : url
    }
}

public struct CommentPage: Sendable, Equatable {
    public var comments: [Comment]
    public var pinned: Comment?
    /// Nil on the last page.
    public var nextOffset: String?
    public var isEnd: Bool
    public var total: Int

    public init(comments: [Comment], pinned: Comment? = nil, nextOffset: String? = nil, isEnd: Bool = true, total: Int = 0) {
        self.comments = comments
        self.pinned = pinned
        self.nextOffset = nextOffset
        self.isEnd = isEnd
        self.total = total
    }
}

public struct ThreadPage: Sendable, Equatable {
    public var root: Comment
    public var replies: [Comment]
    public var total: Int
    public var isEnd: Bool

    public init(root: Comment, replies: [Comment], total: Int, isEnd: Bool) {
        self.root = root
        self.replies = replies
        self.total = total
        self.isEnd = isEnd
    }
}

public struct Emote: Sendable, Equatable {
    /// What the comment text carries for the emote, such as "[doge]".
    public var token: String
    /// Empty for the text (kaomoji) packages, whose token is the picture.
    public var url: String
    public var large: Bool

    public init(token: String, url: String, large: Bool) {
        self.token = token
        self.url = url
        self.large = large
    }
}

public struct EmotePackage: Sendable, Equatable {
    public var id: Int64
    public var name: String
    public var icon: String
    public var isText: Bool
    public var emotes: [Emote]

    public init(id: Int64, name: String, icon: String, isText: Bool, emotes: [Emote]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isText = isText
        self.emotes = emotes
    }
}

extension Emote: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let token = container.text("text"), !token.isEmpty else { throw missing("text", decoder) }
        self.token = token
        url = container.text("url") ?? ""
        large = (container.nested("meta")?.count("size") ?? 1) != 1
    }
}

extension EmotePackage: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        id = container.count("id")
        name = container.text("text") ?? ""
        icon = container.text("url") ?? ""
        isText = container.count("type") == 4
        emotes = (try? container.first([Lossy<Emote>].self, "emote"))?.compactMap(\.value) ?? []
    }
}

struct EmotePanel: Decodable {
    let packages: [EmotePackage]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        packages = try container.first([Lossy<EmotePackage>].self, "packages")?.compactMap(\.value) ?? []
    }
}

struct CommentListData: Decodable {
    let page: CommentPage

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let replies = try container.first([Lossy<Comment>].self, "replies")?.compactMap(\.value) ?? []
        let top = try container.first([Lossy<Comment>].self, "top_replies")?.compactMap(\.value) ?? []
        let cursor = container.nested("cursor")
        let next = cursor?.nested("pagination_reply")?.text("next_offset").flatMap { $0.isEmpty ? nil : $0 }
        var pinned = top.first
        pinned?.isPinned = true
        page = CommentPage(comments: replies, pinned: pinned, nextOffset: next,
                           // Without an offset there is no way to ask for more, whatever is_end says.
                           isEnd: next == nil || cursor?.flag("is_end") == true,
                           total: Int(cursor?.count("all_count") ?? 0))
    }
}

struct CommentThreadData: Decodable {
    let page: ThreadPage

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let root = try container.first(Comment.self, "root") else { throw missing("root", decoder) }
        let replies = try container.first([Lossy<Comment>].self, "replies")?.compactMap(\.value) ?? []
        let paging = container.nested("page")
        let total = Int(paging?.count("count") ?? 0)
        let seen = Int((paging?.count("num") ?? 0) * (paging?.count("size") ?? 0))
        page = ThreadPage(root: root, replies: replies, total: total, isEnd: replies.isEmpty || seen >= total)
    }
}

struct PostedComment: Decodable {
    let reply: Comment

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let reply = try container.first(Comment.self, "reply") else { throw missing("reply", decoder) }
        self.reply = reply
    }
}
