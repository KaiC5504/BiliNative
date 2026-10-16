import Foundation

public struct HLSVideoCodec: Equatable, Sendable {
    public let codecs: String
    public let supplemental: String?
    public let videoRange: String

    public init(codecs: String, supplemental: String?, videoRange: String) {
        self.codecs = codecs
        self.supplemental = supplemental
        self.videoRange = videoRange
    }
}

public enum CodecMapper {
    /// `rewriteHEV1` is true only when the served init segment really was rewritten to `hvc1`
    /// (BTR mode); in direct mode AVPlayer reads Bilibili's original bytes.
    public static func video(codecs: String, qualityID: Int, rewriteHEV1: Bool) -> HLSVideoCodec {
        // Dolby Vision profile 8 is declared as its HEVC base layer plus a supplemental codec, so
        // devices without Dolby Vision still play the base layer.
        if codecs == "dvh1.08.07" || codecs == "dvh1.08.03" {
            return HLSVideoCodec(codecs: "hvc1.2.4.L153.b0", supplemental: "\(codecs)/db4h", videoRange: "HLG")
        }
        if codecs == "dvh1.08.06" {
            return HLSVideoCodec(codecs: "hvc1.2.4.L150", supplemental: "\(codecs)/db1p", videoRange: "PQ")
        }
        if codecs.hasPrefix("dvh1.05") {
            return HLSVideoCodec(codecs: codecs, supplemental: nil, videoRange: "PQ")
        }
        let mapped = rewriteHEV1 && codecs.hasPrefix("hev1") ? "hvc1" + codecs.dropFirst(4) : codecs
        // 125 is 真彩 HDR (HDR10).
        return HLSVideoCodec(codecs: mapped, supplemental: nil, videoRange: qualityID == 125 ? "PQ" : "SDR")
    }

    public static func frameRate(_ text: String?) -> String {
        guard let text, let value = Double(text), value.isFinite, value > 0 else { return "30.000" }
        return String(format: "%.3f", value)
    }
}
