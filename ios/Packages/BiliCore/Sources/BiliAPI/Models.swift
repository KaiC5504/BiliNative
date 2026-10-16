import Foundation
import BiliShared

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where K == AnyKey {
    /// Bilibili spells many fields two ways (baseUrl/base_url); the first present, non-null one wins.
    func first<T: Decodable>(_ type: T.Type, _ keys: String...) throws -> T? {
        for key in keys {
            if let value = try decodeIfPresent(T.self, forKey: AnyKey(key)) { return value }
        }
        return nil
    }

    func nested(_ keys: String...) -> KeyedDecodingContainer<AnyKey>? {
        for key in keys where contains(AnyKey(key)) {
            if let container = try? nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key)) { return container }
        }
        return nil
    }
}

func missing(_ field: String, _ decoder: Decoder) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "missing \(field)"))
}

/// One undecodable element becomes nil instead of failing the whole array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

private struct Ignored: Decodable {
    init(from decoder: Decoder) {}
}

public struct BiliEnvelope<T: Decodable>: Decodable {
    public let code: Int
    public let message: String?
    public let data: T?

    enum CodingKeys: String, CodingKey { case code, message, data }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        // Error replies carry data of another shape, or none; only a success must decode strictly.
        if code == 0 {
            data = try container.decodeIfPresent(T.self, forKey: .data)
        } else {
            data = try? container.decodeIfPresent(T.self, forKey: .data)
        }
    }
}

public struct NavInfo: Decodable, Sendable, Equatable {
    public let isLogin: Bool
    public let mid: Int64?
    public let uname: String?
    public let vipStatus: Int
    public let vipType: Int
    public let imgURL: String
    public let subURL: String

    public var isVip: Bool { vipStatus == 1 }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        isLogin = try container.first(Bool.self, "isLogin") ?? false
        mid = try container.first(Int64.self, "mid")
        uname = try container.first(String.self, "uname")
        vipStatus = try container.first(Int.self, "vipStatus") ?? 0
        vipType = try container.first(Int.self, "vipType") ?? 0
        let images = container.nested("wbi_img")
        imgURL = try images?.first(String.self, "img_url") ?? ""
        subURL = try images?.first(String.self, "sub_url") ?? ""
    }
}

public struct SPIInfo: Decodable, Sendable {
    public let b3: String
    public let b4: String

    enum CodingKeys: String, CodingKey {
        case b3 = "b_3"
        case b4 = "b_4"
    }
}

public struct VideoPage: Decodable, Sendable, Hashable {
    public let cid: Int64
    public let page: Int
    public let part: String
    public let duration: Int

    public init(cid: Int64, page: Int, part: String, duration: Int) {
        self.cid = cid
        self.page = page
        self.part = part
        self.duration = duration
    }
}

public struct VideoView: Decodable, Sendable, Equatable {
    public let bvid: String
    public let aid: Int64
    public let title: String
    public let owner: String?
    public let pages: [VideoPage]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let bvid = try container.first(String.self, "bvid") else { throw missing("bvid", decoder) }
        self.bvid = bvid
        aid = try container.first(Int64.self, "aid") ?? 0
        title = try container.first(String.self, "title") ?? ""
        owner = try container.nested("owner")?.first(String.self, "name")
        pages = try container.first([VideoPage].self, "pages") ?? []
    }
}

public struct DashStream: Decodable, Sendable, Equatable {
    public let id: Int
    public let baseURL: String
    public let backupURLs: [String]
    public let bandwidth: Int
    public let mimeType: String
    public let codecs: String
    public let codecid: Int
    public let width: Int
    public let height: Int
    public let frameRate: String?
    public let initialization: ByteRange
    public let indexRange: ByteRange

    public init(id: Int, baseURL: String, backupURLs: [String], bandwidth: Int, mimeType: String, codecs: String, codecid: Int,
                width: Int, height: Int, frameRate: String?, initialization: ByteRange, indexRange: ByteRange) {
        self.id = id
        self.baseURL = baseURL
        self.backupURLs = backupURLs
        self.bandwidth = bandwidth
        self.mimeType = mimeType
        self.codecs = codecs
        self.codecid = codecid
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.initialization = initialization
        self.indexRange = indexRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        id = try container.first(Int.self, "id") ?? 0
        guard let base = try container.first(String.self, "baseUrl", "base_url") else { throw missing("baseUrl", decoder) }
        baseURL = base
        backupURLs = try container.first([String].self, "backupUrl", "backup_url") ?? []
        bandwidth = try container.first(Int.self, "bandwidth") ?? 0
        mimeType = try container.first(String.self, "mimeType", "mime_type") ?? ""
        codecs = try container.first(String.self, "codecs") ?? ""
        codecid = try container.first(Int.self, "codecid") ?? 0
        width = try container.first(Int.self, "width") ?? 0
        height = try container.first(Int.self, "height") ?? 0
        let rate = try container.first(String.self, "frameRate", "frame_rate")
        frameRate = (rate?.isEmpty ?? true) ? nil : rate
        var ranges: (ByteRange, ByteRange)?
        for key in ["SegmentBase", "segment_base"] {
            guard let segmentBase = container.nested(key) else { continue }
            let start = (try? segmentBase.first(String.self, "Initialization", "initialization")) ?? nil
            let index = (try? segmentBase.first(String.self, "indexRange", "index_range")) ?? nil
            if let start = start.flatMap(ByteRange.parse), let index = index.flatMap(ByteRange.parse) {
                ranges = (start, index)
                break
            }
        }
        guard let (initRange, index) = ranges else { throw missing("SegmentBase", decoder) }
        initialization = initRange
        indexRange = index
    }
}

public struct Dash: Decodable, Sendable, Equatable {
    public let duration: Int
    public let video: [DashStream]
    public let audio: [DashStream]

    public init(duration: Int, video: [DashStream], audio: [DashStream]) {
        self.duration = duration
        self.video = video
        self.audio = audio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        duration = try container.first(Int.self, "duration") ?? 0
        video = try container.first([Lossy<DashStream>].self, "video")?.compactMap(\.value) ?? []
        audio = try container.first([Lossy<DashStream>].self, "audio")?.compactMap(\.value) ?? []
    }
}

public struct QualityOption: Hashable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct PlayURLInfo: Decodable, Sendable {
    public let quality: Int
    public let acceptQuality: [Int]
    public let acceptDescription: [String]
    public let dash: Dash?
    public let hasDurl: Bool
    public let lastPlayTimeMs: Int64
    public let lastPlayCid: Int64

    public init(quality: Int, acceptQuality: [Int], acceptDescription: [String], dash: Dash?, hasDurl: Bool,
                lastPlayTimeMs: Int64 = 0, lastPlayCid: Int64 = 0) {
        self.quality = quality
        self.acceptQuality = acceptQuality
        self.acceptDescription = acceptDescription
        self.dash = dash
        self.hasDurl = hasDurl
        self.lastPlayTimeMs = lastPlayTimeMs
        self.lastPlayCid = lastPlayCid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        quality = try container.first(Int.self, "quality") ?? 0
        acceptQuality = try container.first([Int].self, "accept_quality") ?? []
        acceptDescription = try container.first([String].self, "accept_description") ?? []
        dash = try container.first(Dash.self, "dash")
        let durl = (try? container.first([Ignored].self, "durl")) ?? nil
        hasDurl = !(durl ?? []).isEmpty
        lastPlayTimeMs = try container.first(Int64.self, "last_play_time") ?? 0
        lastPlayCid = try container.first(Int64.self, "last_play_cid") ?? 0
    }

    public var qualityOptions: [QualityOption] {
        zip(acceptQuality, acceptDescription).map { QualityOption(id: $0.0, name: $0.1) }
    }
}
