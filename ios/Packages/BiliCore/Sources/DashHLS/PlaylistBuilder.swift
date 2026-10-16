import Foundation
import BiliShared

public struct HLSTrack: Sendable {
    public let uri: String
    /// ftyp + moov.
    public let initRange: ByteRange
    public let segments: [MediaSegment]

    public init(uri: String, initRange: ByteRange, segments: [MediaSegment]) {
        self.uri = uri
        self.initRange = initRange
        self.segments = segments
    }
}

public struct HLSVariant: Sendable {
    public let codec: HLSVideoCodec
    public let audioCodecs: String
    /// Video plus audio, bits per second.
    public let averageBandwidth: Int
    public let width: Int
    public let height: Int
    public let frameRate: String

    public init(codec: HLSVideoCodec, audioCodecs: String, averageBandwidth: Int, width: Int, height: Int, frameRate: String) {
        self.codec = codec
        self.audioCodecs = audioCodecs
        self.averageBandwidth = averageBandwidth
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }
}

public enum PlaylistBuilder {
    public static func media(_ track: HLSTrack) -> String {
        let target = Int((track.segments.map(\.duration).max() ?? 1).rounded(.up))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(max(1, target))",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-MAP:URI=\"\(track.uri)\",BYTERANGE=\"\(track.initRange.length)@\(track.initRange.start)\"",
        ]
        for segment in track.segments {
            lines.append("#EXTINF:\(String(format: "%.3f", segment.duration)),")
            lines.append("#EXT-X-BYTERANGE:\(segment.range.length)@\(segment.range.start)")
            lines.append(track.uri)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func master(_ variant: HLSVariant, videoPlaylist: String, audioPlaylist: String) -> String {
        var attributes = [
            "BANDWIDTH=\(Int(Double(variant.averageBandwidth) * 1.5))",
            "AVERAGE-BANDWIDTH=\(variant.averageBandwidth)",
            "CODECS=\"\(variant.codec.codecs),\(variant.audioCodecs)\"",
        ]
        if let supplemental = variant.codec.supplemental {
            attributes.append("SUPPLEMENTAL-CODECS=\"\(supplemental)\"")
        }
        attributes += [
            "RESOLUTION=\(variant.width)x\(variant.height)",
            "FRAME-RATE=\(variant.frameRate)",
            "VIDEO-RANGE=\(variant.codec.videoRange)",
            "AUDIO=\"audio\"",
        ]
        let lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"default\",DEFAULT=YES,AUTOSELECT=YES,URI=\"\(audioPlaylist)\"",
            "#EXT-X-STREAM-INF:" + attributes.joined(separator: ","),
            videoPlaylist,
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
