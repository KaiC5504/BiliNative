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

    /// "hang.mp4": every read starts (`onRead`) but never yields; `onEnd` fires when the read stream is torn down.
    static func registerHangingAsset(on server: LocalServer, onRead: @escaping @Sendable () -> Void,
                                     onEnd: @escaping @Sendable () -> Void) -> String {
        let media = MediaResource(totalSize: 10_000, prefix: []) { _ in
            onRead()
            return AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in onEnd() }
            }
        }
        return server.router.register(PlaybackAssets(playlists: [:], media: ["hang.mp4": media]))
    }

    /// ftyp, optionally an empty moov, then a version 0 sidx with one 1000-byte, 2-second
    /// reference. Both tracks of the choice point at the same layout, each with a primary address on
    /// primary.invalid and one backup per host in `backupHosts`.
    static func headerFixture(withMoov: Bool, backupHosts: [String] = ["backup.invalid"]) -> (choice: TrackChoice, bytes: [UInt8], total: Int64) {
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
                       backupURLs: backupHosts.map { "https://\($0)/upgcxcode/\(id).m4s?deadline=1&upsig=sig" }, bandwidth: 1_000_000,
                       mimeType: "video/mp4", codecs: codecs, codecid: 7, width: 1920, height: 1080, frameRate: "30",
                       initialization: ByteRange(start: 0, end: initEnd)!,
                       indexRange: ByteRange(start: initEnd + 1, end: Int64(bytes.count) - 1)!)
        }
        return (TrackChoice(video: stream(80, "avc1.640032"), audio: stream(30280, "mp4a.40.2")), bytes, total)
    }

    enum FixtureAnswer: Sendable {
        case refuse
        case wholeFile
        case wrongRange
    }

    /// Serves `bytes` as the start of a `total`-byte file. Hosts in `answers` misbehave instead:
    /// 403, 200 with the whole file, or 206 labelled with a range one byte off.
    struct FixtureTransport: RangeTransport {
        let bytes: [UInt8]
        let total: Int64
        let answers: [String: FixtureAnswer]

        func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
            func body(_ chunk: [UInt8]) -> AsyncThrowingStream<[UInt8], Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(chunk)
                    continuation.finish()
                }
            }
            guard range.start < Int64(bytes.count) else {
                return TransportResponse(status: 416, headers: ["content-range": "bytes */\(total)"], body: body([]))
            }
            let slice = Array(bytes[Int(range.start)...Int(min(range.end, Int64(bytes.count) - 1))])
            switch answers[url.host ?? ""] {
            case .refuse:
                return TransportResponse(status: 403, headers: [:], body: body([]))
            case .wholeFile:
                return TransportResponse(status: 200, headers: ["content-length": "\(total)"], body: body(bytes))
            case .wrongRange:
                return TransportResponse(status: 206, headers: ["content-range": "bytes \(range.start + 1)-\(range.end + 1)/\(total)"],
                                         body: body(slice))
            case nil:
                return TransportResponse(status: 206, headers: ["content-range": "bytes \(range.start)-\(range.end)/\(total)"],
                                         body: body(slice))
            }
        }
    }
}
#endif
