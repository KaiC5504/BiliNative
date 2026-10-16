import Foundation
import BiliShared

extension KeyedDecodingContainer where K == AnyKey {
    /// Counts are numbers, but a hidden one arrives as a string such as "--".
    func count(_ keys: String...) -> Int64 {
        for key in keys {
            if let number = try? decodeIfPresent(Int64.self, forKey: AnyKey(key)) { return number }
            if let text = try? decodeIfPresent(String.self, forKey: AnyKey(key)) { return Int64(text) ?? 0 }
        }
        return 0
    }
}

public struct VideoOwner: Decodable, Sendable, Equatable {
    public let mid: Int64
    public let name: String
    public let face: String

    public init(mid: Int64, name: String, face: String) {
        self.mid = mid
        self.name = name
        self.face = face
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        mid = try container.first(Int64.self, "mid") ?? 0
        name = try container.first(String.self, "name") ?? ""
        face = try container.first(String.self, "face") ?? ""
    }
}

public struct VideoStat: Decodable, Sendable, Equatable {
    public let view: Int64
    public let danmaku: Int64
    public let reply: Int64
    public let favorite: Int64
    public let coin: Int64
    public let share: Int64
    public let like: Int64

    public init(view: Int64, danmaku: Int64, reply: Int64, favorite: Int64, coin: Int64, share: Int64, like: Int64) {
        self.view = view
        self.danmaku = danmaku
        self.reply = reply
        self.favorite = favorite
        self.coin = coin
        self.share = share
        self.like = like
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        view = container.count("view")
        danmaku = container.count("danmaku")
        reply = container.count("reply")
        favorite = container.count("favorite", "fav")
        coin = container.count("coin")
        share = container.count("share")
        like = container.count("like")
    }
}

public struct DescPart: Sendable, Equatable {
    public let text: String
    public let mentionMid: Int64?

    public init(text: String, mentionMid: Int64? = nil) {
        self.text = text
        self.mentionMid = mentionMid
    }
}

private struct DescEntry: Decodable {
    let part: DescPart?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let text = try container.first(String.self, "raw_text") else { part = nil; return }
        var mid: Int64?
        if try container.first(Int.self, "type") == 2 { mid = try container.first(Int64.self, "biz_id") }
        part = DescPart(text: text, mentionMid: mid)
    }
}

public struct SeasonEpisode: Decodable, Sendable, Equatable {
    public let aid: Int64
    public let bvid: String
    public let cid: Int64
    public let title: String
    public let cover: String
    public let duration: Int
    public let pubdate: Int64
    public let views: Int64
    public let danmaku: Int64

    public init(aid: Int64, bvid: String, cid: Int64, title: String, cover: String, duration: Int, pubdate: Int64,
                views: Int64, danmaku: Int64) {
        self.aid = aid
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.cover = cover
        self.duration = duration
        self.pubdate = pubdate
        self.views = views
        self.danmaku = danmaku
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let arc = container.nested("arc")
        let page = container.nested("page")
        guard let bvid = try container.first(String.self, "bvid") ?? arc?.first(String.self, "bvid"), !bvid.isEmpty else {
            throw missing("bvid", decoder)
        }
        guard let cid = try container.first(Int64.self, "cid") ?? page?.first(Int64.self, "cid") else {
            throw missing("cid", decoder)
        }
        self.bvid = bvid
        self.cid = cid
        aid = try container.first(Int64.self, "aid") ?? arc?.first(Int64.self, "aid") ?? 0
        title = try container.first(String.self, "title") ?? arc?.first(String.self, "title") ?? ""
        cover = try arc?.first(String.self, "pic") ?? ""
        duration = try arc?.first(Int.self, "duration") ?? page?.first(Int.self, "duration") ?? 0
        pubdate = try arc?.first(Int64.self, "pubdate") ?? 0
        let stat = arc?.nested("stat")
        views = stat?.count("view") ?? 0
        danmaku = stat?.count("danmaku") ?? 0
    }
}

public struct SeasonSection: Decodable, Sendable, Equatable {
    public let id: Int64
    public let title: String
    public let episodes: [SeasonEpisode]

    public init(id: Int64, title: String, episodes: [SeasonEpisode]) {
        self.id = id
        self.title = title
        self.episodes = episodes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        id = try container.first(Int64.self, "id") ?? 0
        title = try container.first(String.self, "title") ?? ""
        episodes = try container.first([Lossy<SeasonEpisode>].self, "episodes")?.compactMap(\.value) ?? []
    }
}

public struct UgcSeason: Decodable, Sendable, Equatable {
    public let id: Int64
    public let title: String
    public let intro: String
    public let sections: [SeasonSection]

    public init(id: Int64, title: String, intro: String, sections: [SeasonSection]) {
        self.id = id
        self.title = title
        self.intro = intro
        self.sections = sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        id = try container.first(Int64.self, "id") ?? 0
        title = try container.first(String.self, "title") ?? ""
        intro = try container.first(String.self, "intro") ?? ""
        sections = try container.first([Lossy<SeasonSection>].self, "sections")?.compactMap(\.value) ?? []
    }
}

public struct StaffMember: Decodable, Sendable, Equatable {
    public let mid: Int64
    public let title: String
    public let name: String
    public let face: String

    public init(mid: Int64, title: String, name: String, face: String) {
        self.mid = mid
        self.title = title
        self.name = name
        self.face = face
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        mid = try container.first(Int64.self, "mid") ?? 0
        title = try container.first(String.self, "title") ?? ""
        name = try container.first(String.self, "name") ?? ""
        face = try container.first(String.self, "face") ?? ""
    }
}

private struct HonorEntry: Decodable {
    let desc: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        desc = try container.first(String.self, "desc") ?? ""
    }
}

public struct VideoDetail: Decodable, Sendable, Equatable {
    public let bvid: String
    public let aid: Int64
    public let title: String
    public let cover: String
    public let pubdate: Int64
    public let duration: Int
    public let desc: String
    public let descParts: [DescPart]
    public let copyright: Int
    public let owner: VideoOwner
    public let stat: VideoStat
    public let pages: [VideoPage]
    public let season: UgcSeason?
    public let staff: [StaffMember]
    /// The shape as displayed: already swapped when the file is stored rotated (`dimension.rotate == 1`).
    public let width: Int
    public let height: Int
    public let honor: String?
    /// Set for bangumi and other pages the ordinary video page cannot show.
    public let redirectURL: String?

    public var isVertical: Bool { height > width }

    public init(bvid: String, aid: Int64, title: String, cover: String, pubdate: Int64, duration: Int, desc: String,
                descParts: [DescPart], copyright: Int, owner: VideoOwner, stat: VideoStat, pages: [VideoPage],
                season: UgcSeason?, staff: [StaffMember], width: Int, height: Int, honor: String?, redirectURL: String?) {
        self.bvid = bvid
        self.aid = aid
        self.title = title
        self.cover = cover
        self.pubdate = pubdate
        self.duration = duration
        self.desc = desc
        self.descParts = descParts
        self.copyright = copyright
        self.owner = owner
        self.stat = stat
        self.pages = pages
        self.season = season
        self.staff = staff
        self.width = width
        self.height = height
        self.honor = honor
        self.redirectURL = redirectURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let bvid = try container.first(String.self, "bvid") else { throw missing("bvid", decoder) }
        self.bvid = bvid
        aid = try container.first(Int64.self, "aid") ?? 0
        title = try container.first(String.self, "title") ?? ""
        cover = try container.first(String.self, "pic") ?? ""
        pubdate = try container.first(Int64.self, "pubdate") ?? 0
        duration = try container.first(Int.self, "duration") ?? 0
        let desc = try container.first(String.self, "desc") ?? ""
        self.desc = desc
        let parts = (try? container.first([Lossy<DescEntry>].self, "desc_v2"))?.compactMap { $0.value?.part } ?? []
        descParts = parts.isEmpty && !desc.isEmpty ? [DescPart(text: desc)] : parts
        copyright = try container.first(Int.self, "copyright") ?? 0
        owner = (try? container.first(VideoOwner.self, "owner")) ?? VideoOwner(mid: 0, name: "", face: "")
        stat = (try? container.first(VideoStat.self, "stat")) ?? VideoStat(view: 0, danmaku: 0, reply: 0, favorite: 0, coin: 0, share: 0, like: 0)
        pages = try container.first([Lossy<VideoPage>].self, "pages")?.compactMap(\.value) ?? []
        season = try? container.first(UgcSeason.self, "ugc_season")
        staff = (try? container.first([Lossy<StaffMember>].self, "staff"))?.compactMap(\.value) ?? []
        let dimension = container.nested("dimension")
        let rawWidth = try dimension?.first(Int.self, "width") ?? 0
        let rawHeight = try dimension?.first(Int.self, "height") ?? 0
        let rotated = try dimension?.first(Int.self, "rotate") == 1
        width = rotated ? rawHeight : rawWidth
        height = rotated ? rawWidth : rawHeight
        let honors = (try? container.nested("honor_reply")?.first([Lossy<HonorEntry>].self, "honor"))?.compactMap(\.value) ?? []
        honor = honors.first { !$0.desc.isEmpty }?.desc
        let redirect = try container.first(String.self, "redirect_url")
        redirectURL = (redirect ?? "").isEmpty ? nil : redirect
    }
}

public struct Chapter: Sendable, Equatable {
    public let from: Double
    public let to: Double
    public let title: String

    public init(from: Double, to: Double, title: String) {
        self.from = from
        self.to = to
        self.title = title
    }
}

private struct ViewPoint: Decodable {
    let type: Int
    let chapter: Chapter

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        type = try container.first(Int.self, "type") ?? 0
        chapter = try Chapter(from: container.first(Double.self, "from") ?? 0,
                              to: container.first(Double.self, "to") ?? 0,
                              title: container.first(String.self, "content") ?? "")
    }
}

public struct PlayerInfo: Decodable, Sendable, Equatable {
    public let lastPlayCid: Int64
    public let chapters: [Chapter]

    public init(lastPlayCid: Int64, chapters: [Chapter]) {
        self.lastPlayCid = lastPlayCid
        self.chapters = chapters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        lastPlayCid = try container.first(Int64.self, "last_play_cid") ?? 0
        let points = try container.first([Lossy<ViewPoint>].self, "view_points")?.compactMap(\.value) ?? []
        // type 1 is the uploader's highlight marks, not a chapter list.
        chapters = points.first?.type == 2 ? points.filter { $0.type == 2 }.map(\.chapter) : []
    }
}

public struct VideoCard: Decodable, Sendable, Equatable {
    public let aid: Int64
    public let bvid: String
    public let cid: Int64
    public let title: String
    public let cover: String
    public let duration: Int
    public let ownerMid: Int64
    public let ownerName: String
    public let views: Int64
    public let danmaku: Int64
    public let likes: Int64

    public init(aid: Int64, bvid: String, cid: Int64, title: String, cover: String, duration: Int, ownerMid: Int64,
                ownerName: String, views: Int64, danmaku: Int64, likes: Int64) {
        self.aid = aid
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.cover = cover
        self.duration = duration
        self.ownerMid = ownerMid
        self.ownerName = ownerName
        self.views = views
        self.danmaku = danmaku
        self.likes = likes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let bvid = try container.first(String.self, "bvid"), !bvid.isEmpty else { throw missing("bvid", decoder) }
        self.bvid = bvid
        aid = try container.first(Int64.self, "aid") ?? 0
        cid = try container.first(Int64.self, "cid") ?? 0
        title = try container.first(String.self, "title") ?? ""
        cover = try container.first(String.self, "pic") ?? ""
        duration = try container.first(Int.self, "duration") ?? 0
        let owner = container.nested("owner")
        ownerMid = try owner?.first(Int64.self, "mid") ?? 0
        ownerName = try owner?.first(String.self, "name") ?? ""
        let stat = container.nested("stat")
        views = stat?.count("view") ?? 0
        danmaku = stat?.count("danmaku") ?? 0
        likes = stat?.count("like") ?? 0
    }
}
