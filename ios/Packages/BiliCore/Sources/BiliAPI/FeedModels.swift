import Foundation

public struct FeedCard: Identifiable, Sendable, Equatable {
    public let aid: Int64
    public let bvid: String
    public let cid: Int64
    public let title: String
    public let cover: String
    public let duration: Int
    public let views: Int64
    public let danmaku: Int64
    public let ownerName: String
    public let ownerMid: Int64
    /// `rcmd_reason.content`, such as "2万点赞"; nil when the server gave no reason.
    public let reason: String?
    public let isVertical: Bool

    public var id: String { bvid }

    public init(aid: Int64, bvid: String, cid: Int64, title: String, cover: String, duration: Int, views: Int64, danmaku: Int64,
                ownerName: String, ownerMid: Int64, reason: String?, isVertical: Bool) {
        self.aid = aid
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.cover = cover
        self.duration = duration
        self.views = views
        self.danmaku = danmaku
        self.ownerName = ownerName
        self.ownerMid = ownerMid
        self.reason = reason
        self.isVertical = isVertical
    }
}

extension FeedCard: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let bvid = try container.first(String.self, "bvid"), !bvid.isEmpty else { throw missing("bvid", decoder) }
        let owner = container.nested("owner")
        let stat = container.nested("stat")
        let reason = try container.nested("rcmd_reason")?.first(String.self, "content")
        // The web feed names the aid `id`.
        self.init(aid: try container.first(Int64.self, "id", "aid") ?? 0,
                  bvid: bvid,
                  cid: try container.first(Int64.self, "cid") ?? 0,
                  title: try container.first(String.self, "title") ?? "",
                  cover: try container.first(String.self, "pic") ?? "",
                  duration: try container.first(Int.self, "duration") ?? 0,
                  views: stat?.count("view") ?? 0,
                  danmaku: stat?.count("danmaku") ?? 0,
                  ownerName: try owner?.first(String.self, "name") ?? "",
                  ownerMid: try owner?.first(Int64.self, "mid") ?? 0,
                  reason: (reason ?? "").isEmpty ? nil : reason,
                  isVertical: (try? Self.isVertical(container.nested("dimension"))) ?? false)
    }

    /// A file stored rotated (`rotate == 1`) is shown with width and height swapped, as in `VideoDetail`.
    /// The web feed sends no `dimension` at all, so this is false for every card it returns today.
    private static func isVertical(_ dimension: KeyedDecodingContainer<AnyKey>?) throws -> Bool {
        let width = try dimension?.first(Int.self, "width") ?? 0
        let height = try dimension?.first(Int.self, "height") ?? 0
        let rotated = try dimension?.first(Int.self, "rotate") == 1
        return rotated ? width > height : height > width
    }
}

public enum HistoryDeviceKind: Sendable, Equatable {
    case phone
    case pc
    case padOrTV
}

public struct HistoryItem: Identifiable, Sendable, Equatable {
    public let bvid: String
    public let cid: Int64
    public let title: String
    public let cover: String
    public let ownerName: String
    /// Seconds watched; -1 means watched to the end.
    public let progress: Int
    public let duration: Int
    public let viewAt: Int64
    /// `history.dt`, the platform the video was watched on.
    public let device: Int
    public let part: String?

    /// One video can come back on two pages when it is watched again between loads, so the time is part of the identity.
    public var id: String { "\(bvid)@\(viewAt)" }

    public var deviceKind: HistoryDeviceKind {
        switch device {
        case 1, 3, 5, 7: return .phone
        case 2, 33: return .pc
        default: return .padOrTV
        }
    }

    public init(bvid: String, cid: Int64, title: String, cover: String, ownerName: String, progress: Int, duration: Int,
                viewAt: Int64, device: Int, part: String?) {
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.cover = cover
        self.ownerName = ownerName
        self.progress = progress
        self.duration = duration
        self.viewAt = viewAt
        self.device = device
        self.part = part
    }
}

extension HistoryItem: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let history = container.nested("history")
        guard let bvid = try history?.first(String.self, "bvid"), !bvid.isEmpty else { throw missing("bvid", decoder) }
        // The request already asks for videos only; this keeps a bangumi or live row out if the filter is ever ignored.
        if let business = try history?.first(String.self, "business"), !business.isEmpty, business != "archive" {
            throw missing("archive business", decoder)
        }
        let part = try history?.first(String.self, "part")
        self.init(bvid: bvid,
                  cid: try history?.first(Int64.self, "cid") ?? 0,
                  title: try container.first(String.self, "title") ?? "",
                  cover: try container.first(String.self, "cover") ?? "",
                  ownerName: try container.first(String.self, "author_name") ?? "",
                  progress: try container.first(Int.self, "progress") ?? 0,
                  duration: try container.first(Int.self, "duration") ?? 0,
                  viewAt: try container.first(Int64.self, "view_at") ?? 0,
                  device: try history?.first(Int.self, "dt") ?? 0,
                  part: (part ?? "").isEmpty ? nil : part)
    }
}

/// Where the next page of history starts: the last row's target id and view time.
public struct HistoryCursor: Sendable, Equatable {
    public let max: Int64
    public let viewAt: Int64

    public init(max: Int64, viewAt: Int64) {
        self.max = max
        self.viewAt = viewAt
    }
}

public struct HistoryPage: Sendable, Equatable {
    public let items: [HistoryItem]
    /// nil once there is nothing further to load.
    public let next: HistoryCursor?

    public init(items: [HistoryItem], next: HistoryCursor?) {
        self.items = items
        self.next = next
    }
}
