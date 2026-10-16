import Foundation
import BiliAPI
import Ripper

struct OverlayStats: Equatable {
    var firstFrameMs: Double?
    var lastSeekMs: Double?
    var worstSeekMs: Double?
    var stalls = 0
    var downloadBps: Double = 0
    var ripper: RipperStats?
}

/// The video stream handed to AVPlayer. Direct mode can play another codec than BTR mode, so the overlay shows it.
struct PlayingStream: Equatable {
    let quality: Int
    let codec: String
    /// Bits per second, as Bilibili declares the stream.
    let bandwidth: Int

    init(_ stream: DashStream) {
        quality = stream.id
        codec = Self.codecName(stream)
        bandwidth = stream.bandwidth
    }

    static func codecName(_ stream: DashStream) -> String {
        let kind = TrackSelector.codecKind(stream)
        if kind == "dolby" { return "杜比视界" }
        return VideoCodec(rawValue: kind)?.label ?? String(stream.codecs.prefix { $0 != "." })
    }

    func line(qualityName: String?) -> String {
        let rate = bandwidth >= 1_000_000 ? String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000) : "\(bandwidth / 1000) kbps"
        return "\(qualityName ?? String(quality)) · \(codec) · \(rate)"
    }
}
