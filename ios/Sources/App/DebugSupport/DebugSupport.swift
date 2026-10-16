#if DEBUG
import Foundation
import BiliShared
import BiliAPI
import LocalHTTP
import Ripper

/// Helpers for the simulator tests, compiled into Debug builds only. The test target links no
/// engine modules of its own, so engine values are built here inside the app module.
enum DebugSupport {
    static func makeRouter() -> PlaybackRouter { PlaybackRouter() }

    static func staticContent(size: Int, range: ClosedRange<Int>) -> [UInt8] {
        range.map { UInt8(truncatingIfNeeded: $0 &* 13) }
    }

    /// master.m3u8 plus a media file "v.mp4" whose first 100 bytes come from memory.
    static func registerStaticAssets(on server: LocalServer, size: Int, onRead: (@Sendable () -> Void)? = nil) -> String {
        let all = staticContent(size: size, range: 0...(size - 1))
        let media = MediaResource(totalSize: Int64(size), prefix: Array(all[0..<100])) { range in
            onRead?()
            return AsyncThrowingStream { continuation in
                continuation.yield(Array(all[Int(range.start)...Int(range.end)]))
                continuation.finish()
            }
        }
        return server.router.register(PlaybackAssets(playlists: ["master.m3u8": "#EXTM3U\n"], media: ["v.mp4": media]))
    }

    /// ftyp, optionally an empty moov, then a version 0 sidx with one 1000-byte, 2-second
    /// reference. Both tracks of the choice point at the same layout, each with a primary address on
    /// primary.invalid and one backup on backup.invalid.
    static func headerFixture(withMoov: Bool) -> (choice: TrackChoice, bytes: [UInt8], total: Int64) {
        func uint32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) } }
        func box(_ type: String, _ payload: [UInt8]) -> [UInt8] { uint32(8 + payload.count) + Array(type.utf8) + payload }
        let ftyp = box("ftyp", Array("isom".utf8) + uint32(0))
        let moov = withMoov ? box("moov", []) : []
        let sidx = box("sidx", uint32(0) + uint32(1) + uint32(1000) + uint32(0) + uint32(0) + [0, 0, 0, 1]
                                + uint32(1000) + uint32(2000) + uint32(0))
        let initEnd = Int64(ftyp.count + moov.count) - 1
        let bytes = ftyp + moov + sidx
        let total = Int64(bytes.count) + 1000
        func stream(_ id: Int, _ codecs: String) -> DashStream {
            DashStream(id: id, baseURL: "https://primary.invalid/upgcxcode/\(id).m4s?deadline=1&upsig=sig",
                       backupURLs: ["https://backup.invalid/upgcxcode/\(id).m4s?deadline=1&upsig=sig"], bandwidth: 1_000_000,
                       mimeType: "video/mp4", codecs: codecs, codecid: 7, width: 1920, height: 1080, frameRate: "30",
                       initialization: ByteRange(start: 0, end: initEnd)!,
                       indexRange: ByteRange(start: initEnd + 1, end: Int64(bytes.count) - 1)!)
        }
        return (TrackChoice(video: stream(80, "avc1.640032"), audio: stream(30280, "mp4a.40.2")), bytes, total)
    }

    /// Serves `bytes` as the start of a `total`-byte file; hosts in `refusing` answer 403.
    struct FixtureTransport: RangeTransport {
        let bytes: [UInt8]
        let total: Int64
        let refusing: Set<String>

        func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
            if refusing.contains(url.host ?? "") {
                return TransportResponse(status: 403, headers: [:], body: AsyncThrowingStream { $0.finish() })
            }
            let slice = Array(bytes[Int(range.start)...Int(min(range.end, Int64(bytes.count) - 1))])
            return TransportResponse(status: 206, headers: ["content-range": "bytes \(range.start)-\(range.end)/\(total)"],
                                     body: AsyncThrowingStream { continuation in
                                         continuation.yield(slice)
                                         continuation.finish()
                                     })
        }
    }
}
#endif
