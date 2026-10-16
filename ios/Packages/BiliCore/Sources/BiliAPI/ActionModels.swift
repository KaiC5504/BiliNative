import Foundation

/// Some endpoints answer a flag as 0/1, others as true/false.
private func flag(_ container: KeyedDecodingContainer<AnyKey>, _ keys: String...) -> Bool {
    for key in keys {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: AnyKey(key)) { return value }
        if let number = try? container.decodeIfPresent(Int.self, forKey: AnyKey(key)) { return number != 0 }
    }
    return false
}

public struct VideoRelation: Decodable, Sendable, Equatable {
    public let like: Bool
    public let dislike: Bool
    public let favorite: Bool
    public let attention: Bool
    /// Coins this account has given the video, 0 to 2.
    public let coins: Int

    public init(like: Bool, dislike: Bool, favorite: Bool, attention: Bool, coins: Int) {
        self.like = like
        self.dislike = dislike
        self.favorite = favorite
        self.attention = attention
        self.coins = coins
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        like = flag(container, "like")
        dislike = flag(container, "dislike")
        favorite = flag(container, "favorite")
        attention = flag(container, "attention")
        coins = Int(container.count("coin"))
    }
}

public struct UploaderCard: Decodable, Sendable, Equatable {
    public let mid: Int64
    public let name: String
    public let face: String
    public let fans: Int64
    public let videos: Int64
    public let isVip: Bool
    public let following: Bool

    public init(mid: Int64, name: String, face: String, fans: Int64, videos: Int64, isVip: Bool, following: Bool) {
        self.mid = mid
        self.name = name
        self.face = face
        self.fans = fans
        self.videos = videos
        self.isVip = isVip
        self.following = following
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let card = container.nested("card") else { throw missing("card", decoder) }
        // The card spells mid as a string.
        mid = card.count("mid")
        name = try card.first(String.self, "name") ?? ""
        face = try card.first(String.self, "face") ?? ""
        fans = container.count("follower")
        videos = container.count("archive_count")
        isVip = (try? card.nested("vip")?.first(Int.self, "status", "vipStatus")) == 1
        following = flag(container, "following")
    }
}

public struct TripleResult: Decodable, Sendable, Equatable {
    public let like: Bool
    public let coin: Bool
    public let favorite: Bool
    /// Coins spent, 0 when the account had none to give.
    public let multiply: Int

    public init(like: Bool, coin: Bool, favorite: Bool, multiply: Int) {
        self.like = like
        self.coin = coin
        self.favorite = favorite
        self.multiply = multiply
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        like = flag(container, "like")
        coin = flag(container, "coin")
        favorite = flag(container, "fav", "favorite")
        multiply = Int(container.count("multiply"))
    }
}

public struct FavFolder: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let title: String
    public let count: Int
    public let isPrivate: Bool
    /// Whether the video the list was asked about is already in this folder.
    public let contains: Bool
    public let isDefault: Bool

    public init(id: Int64, title: String, count: Int, isPrivate: Bool, contains: Bool, isDefault: Bool) {
        self.id = id
        self.title = title
        self.count = count
        self.isPrivate = isPrivate
        self.contains = contains
        self.isDefault = isDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let id = try container.first(Int64.self, "id") else { throw missing("id", decoder) }
        self.id = id
        title = try container.first(String.self, "title") ?? ""
        count = Int(container.count("media_count"))
        // attr bit 0 marks a private folder; bit 1 is clear on the account's default folder.
        let attr = Int(container.count("attr"))
        isPrivate = attr & 1 == 1
        isDefault = attr & 2 == 0
        contains = flag(container, "fav_state")
    }
}

public struct VideoTag: Decodable, Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case normal, topic, bgm
    }

    public let id: Int64
    public let name: String
    public let kind: Kind

    public init(id: Int64, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let name = try container.first(String.self, "tag_name") else { throw missing("tag_name", decoder) }
        self.name = name
        id = try container.first(Int64.self, "tag_id") ?? 0
        switch try container.first(String.self, "tag_type") {
        case "topic": kind = .topic
        case "bgm": kind = .bgm
        default: kind = .normal
        }
    }
}
