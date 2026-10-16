public enum VideoCodec: String, CaseIterable, Codable, Sendable {
    case hevc, av1, avc

    public var codecid: Int {
        switch self {
        case .hevc: return 12
        case .av1: return 13
        case .avc: return 7
        }
    }

    public var label: String {
        switch self {
        case .hevc: return "HEVC"
        case .av1: return "AV1"
        case .avc: return "H.264"
        }
    }
}

public struct TrackChoice: Sendable, Equatable {
    public let video: DashStream
    public let audio: DashStream

    public init(video: DashStream, audio: DashStream) {
        self.video = video
        self.audio = audio
    }
}

public enum TrackSelector {
    /// The highest quality not above `quality` (or the lowest offered), then the first codec of
    /// `codecOrder` that quality has, else whatever it has.
    public static func choose(_ dash: Dash, quality: Int, codecOrder: [VideoCodec], excludeDolbyVision: Bool = false) -> TrackChoice? {
        guard let audio = bestAudio(dash.audio) else { return nil }
        var videos = dash.video
        if excludeDolbyVision {
            videos.removeAll { codecKind($0) == "dolby" }
        }
        let qualities = Set(videos.map(\.id)).sorted(by: >)
        guard let picked = qualities.first(where: { $0 <= quality }) ?? qualities.last else { return nil }
        let candidates = videos.filter { $0.id == picked }
        for codec in codecOrder {
            if let video = candidates.first(where: { $0.codecid == codec.codecid }) {
                return TrackChoice(video: video, audio: audio)
            }
        }
        return candidates.first.map { TrackChoice(video: $0, audio: audio) }
    }

    /// AAC only: 30280 (192K) > 30232 (132K) > 30216 (64K). Dolby and Hi-Res are later milestones.
    public static func bestAudio(_ audio: [DashStream]) -> DashStream? {
        let rank = [30280: 3, 30232: 2, 30216: 1]
        return audio
            .filter { $0.codecs.hasPrefix("mp4a") }
            .max { (rank[$0.id] ?? 0, $0.bandwidth) < (rank[$1.id] ?? 0, $1.bandwidth) }
    }

    public static func codecKind(_ stream: DashStream) -> String {
        if stream.codecs.hasPrefix("dvh1") || stream.codecs.hasPrefix("dvhe") || stream.id == 126 { return "dolby" }
        switch stream.codecid {
        case 12: return "hevc"
        case 13: return "av1"
        case 7: return "avc"
        default: return "other"
        }
    }
}
