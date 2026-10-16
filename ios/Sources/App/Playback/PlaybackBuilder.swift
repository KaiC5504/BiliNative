import Foundation
import BiliShared
import BiliAPI
import DashHLS
import Ripper
import LocalHTTP
import DevLog

enum PlaybackError: Error, Equatable {
    case noSidx
    case codecUnplayable(String)
    case noTrack
    case serverDown
    /// Neither Bilibili's address nor any backup answered the header request.
    case noSource

    var userMessage: String {
        switch self {
        case .noSidx: return "视频索引无法解析"
        case .codecUnplayable: return "这个编码无法播放，正在换一种"
        case .noTrack: return "没有可播放的清晰度"
        case .serverDown: return "本地加速服务不可用"
        case .noSource: return "视频服务器暂时无法访问"
        }
    }
}

struct PreparedTrack {
    let stream: DashStream
    /// Direct mode only: the address that answered the header request, used as AVPlayer's media URI.
    /// Ripper mode fills in the stream's baseURL and never reads it; the engine picks its own nodes.
    let mediaURL: String
    /// Bytes 0 through the end of the SIDX, with the init segment already patched when needed.
    let headers: [UInt8]
    let totalSize: Int64
    let segments: [MediaSegment]
    var initRange: ByteRange { stream.initialization }
}

struct PreparedPlayback {
    let video: PreparedTrack
    let audio: PreparedTrack
    /// True when the served init segment was renamed from hev1 to hvc1.
    let rewroteHEV1: Bool
}

enum PlaybackBuilder {
    static func prepare(choice: TrackChoice,
                        fetchHeaders: (TrackKind, DashStream) async throws -> (bytes: [UInt8], total: Int64)) async throws -> PreparedPlayback {
        try await assemble(choice) { kind, stream in
            let fetched = try await fetchHeaders(kind, stream)
            return (fetched.bytes, fetched.total, stream.baseURL)
        }
    }

    /// Direct mode: each track plays from whichever of its addresses answered the header request.
    /// Both tracks' headers are fetched at once; each address gets `candidateSeconds` before the next is tried.
    static func prepareDirect(choice: TrackChoice, transport: RangeTransport, candidateSeconds: Double = 6) async throws -> PreparedPlayback {
        async let video = directHeaders(choice.video, transport: transport, candidateSeconds: candidateSeconds)
        async let audio = directHeaders(choice.audio, transport: transport, candidateSeconds: candidateSeconds)
        let fetched = try await (video: video, audio: audio)
        return try await assemble(choice) { kind, _ in kind == .video ? fetched.video : fetched.audio }
    }

    private static func assemble(_ choice: TrackChoice,
                                 fetch: (TrackKind, DashStream) async throws -> (bytes: [UInt8], total: Int64, url: String)) async throws -> PreparedPlayback {
        func track(_ kind: TrackKind, _ stream: DashStream) async throws -> (PreparedTrack, Bool) {
            let fetched = try await fetch(kind, stream)
            guard let segments = SidxParser.parse(fetched.bytes, absoluteStart: 0) else {
                Logger.shared.warn(.player, "headers unusable", ["track": .init(kind.rawValue), "reason": "sidx missing or not flat"])
                throw PlaybackError.noSidx
            }
            // InitSegmentFixer reports a buffer without moov as unchanged, and the playlist's
            // EXT-X-MAP must be served whole from these bytes.
            guard hasCompleteMoov(fetched.bytes, initRange: stream.initialization) else {
                Logger.shared.warn(.player, "headers unusable", ["track": .init(kind.rawValue), "reason": "no complete moov in init range"])
                throw PlaybackError.noSidx
            }
            var headers = fetched.bytes
            var rewrote = false
            if kind == .video {
                switch InitSegmentFixer.fixHEV1(headers) {
                case .unchanged: break
                case .rewritten(let fixed):
                    headers = fixed
                    rewrote = true
                case .unplayable(let reason):
                    throw PlaybackError.codecUnplayable(reason)
                }
            }
            return (PreparedTrack(stream: stream, mediaURL: fetched.url, headers: headers, totalSize: fetched.total, segments: segments), rewrote)
        }
        let (video, rewrote) = try await track(.video, choice.video)
        let (audio, _) = try await track(.audio, choice.audio)
        return PreparedPlayback(video: video, audio: audio, rewroteHEV1: rewrote)
    }

    private static func hasCompleteMoov(_ bytes: [UInt8], initRange: ByteRange) -> Bool {
        guard initRange.end < Int64(bytes.count) else { return false }
        return BoxReader.boxes(in: bytes, from: 0, to: Int(initRange.end) + 1).contains { $0.type == "moov" }
    }

    static func ripperAssets(_ prepared: PreparedPlayback, session: RipperSession) -> PlaybackAssets {
        let playlists = playlists(prepared, videoURI: "v.mp4", audioURI: "a.mp4", videoPlaylist: "v.m3u8", audioPlaylist: "a.m3u8",
                                  rewriteHEV1: prepared.rewroteHEV1)
        func resource(_ kind: TrackKind, _ track: PreparedTrack) -> MediaResource {
            MediaResource(totalSize: track.totalSize, prefix: track.headers) { range in session.read(kind, range) }
        }
        return PlaybackAssets(playlists: playlists, media: ["v.mp4": resource(.video, prepared.video), "a.mp4": resource(.audio, prepared.audio)])
    }

    /// AVPlayer reads Bilibili's original bytes in direct mode, so the codec string stays as given.
    static func directPlaylists(_ prepared: PreparedPlayback, token: String) -> [String: String] {
        playlists(prepared, videoURI: prepared.video.mediaURL, audioURI: prepared.audio.mediaURL,
                  videoPlaylist: DirectPlaylistLoader.url(token: token, name: "v.m3u8").absoluteString,
                  audioPlaylist: DirectPlaylistLoader.url(token: token, name: "a.m3u8").absoluteString, rewriteHEV1: false)
    }

    private static func playlists(_ prepared: PreparedPlayback, videoURI: String, audioURI: String, videoPlaylist: String,
                                  audioPlaylist: String, rewriteHEV1: Bool) -> [String: String] {
        let video = prepared.video.stream
        let audio = prepared.audio.stream
        let variant = HLSVariant(codec: CodecMapper.video(codecs: video.codecs, qualityID: video.id, rewriteHEV1: rewriteHEV1),
                                 audioCodecs: audio.codecs.isEmpty ? "mp4a.40.2" : audio.codecs,
                                 averageBandwidth: video.bandwidth + audio.bandwidth,
                                 width: video.width, height: video.height, frameRate: CodecMapper.frameRate(video.frameRate))
        return [
            "master.m3u8": PlaylistBuilder.master(variant, videoPlaylist: videoPlaylist, audioPlaylist: audioPlaylist),
            "v.m3u8": PlaylistBuilder.media(HLSTrack(uri: videoURI, initRange: prepared.video.initRange, segments: prepared.video.segments)),
            "a.m3u8": PlaylistBuilder.media(HLSTrack(uri: audioURI, initRange: prepared.audio.initRange, segments: prepared.audio.segments)),
        ]
    }

    /// One plain request per address, Bilibili's own first, then its backups; the first that answers
    /// with the whole range wins. Some accounts get a primary that refuses everything (403) next to
    /// working backups on the same host.
    private static func directHeaders(_ stream: DashStream, transport: RangeTransport,
                                      candidateSeconds: Double) async throws -> (bytes: [UInt8], total: Int64, url: String) {
        guard let range = ByteRange(start: 0, end: stream.indexRange.end) else { throw PlaybackError.noSidx }
        let candidates = [stream.baseURL] + stream.backupURLs
        var refused = 0
        for address in candidates {
            do {
                guard let url = URL(string: address) else { throw RipperError.invalidURL }
                let (bytes, total) = try await within(candidateSeconds) { try await wholeRange(url, range, transport: transport) }
                Logger.shared.info(.player, "direct source", ["url": .init(address), "refused": .init(refused),
                                                              "candidates": .init(candidates.count)])
                return (bytes, total, address)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                refused += 1
                // The logger shortens the signed URL to host, path and deadline.
                Logger.shared.warn(.player, "direct headers failed", ["url": .init(address), "error": .init(String(describing: error))])
            }
        }
        Logger.shared.error(.player, "no direct source", ["refused": .init(refused), "candidates": .init(candidates.count)])
        throw PlaybackError.noSource
    }

    private static func wholeRange(_ url: URL, _ range: ByteRange, transport: RangeTransport) async throws -> (bytes: [UInt8], total: Int64) {
        let response = try await transport.fetch(url, range: range)
        guard response.status == 206, let contentRange = ContentRange.parse(response.headers["content-range"]),
              contentRange.range == range, let total = contentRange.total else {
            throw RipperError.badResponse(status: response.status)
        }
        var bytes: [UInt8] = []
        for try await chunk in response.body { bytes += chunk }
        guard Int64(bytes.count) == range.length else { throw RipperError.lengthMismatch(got: Int64(bytes.count), expected: range.length) }
        return (bytes, total)
    }

    struct CandidateTimeout: Error {}

    /// Runs `body` with a deadline; on timeout `body` is cancelled and CandidateTimeout thrown.
    static func within<T: Sendable>(_ seconds: Double, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let value = first else { throw CandidateTimeout() }
            return value
        }
    }
}
