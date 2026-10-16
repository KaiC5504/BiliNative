#if DEBUG
import Foundation
import BiliShared
import BiliAPI

extension DebugSupport {
    /// A Dash with one video stream per entry and one AAC audio stream; byte ranges are placeholders.
    static func codecDash(_ streams: [(id: Int, codecid: Int, codecs: String)]) -> Dash {
        func stream(_ id: Int, _ codecid: Int, _ codecs: String) -> DashStream {
            DashStream(id: id, baseURL: "https://primary.invalid/\(id)-\(codecid).m4s", backupURLs: [], bandwidth: 1_000_000,
                       mimeType: "video/mp4", codecs: codecs, codecid: codecid, width: 1920, height: 1080, frameRate: "30",
                       initialization: ByteRange(start: 0, end: 99)!, indexRange: ByteRange(start: 100, end: 199)!)
        }
        return Dash(duration: 10, video: streams.map { stream($0.id, $0.codecid, $0.codecs) },
                    audio: [stream(30280, 0, "mp4a.40.2")])
    }
}
#endif
