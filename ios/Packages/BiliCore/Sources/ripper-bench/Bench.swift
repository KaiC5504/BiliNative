import Foundation
import BiliShared
import BiliAPI
import DashHLS
import DevLog
import Ripper

/// Downloads the start of a real video twice, over one connection and through Ripper, and prints both.
/// Usage: ripper-bench --bv BV1xxxxxxxxx [--cookies path] [--mb 16] [--mode overseas|mainland] [--quality 80] [--codec hevc|av1|avc]
///        ripper-bench --playurl saved-playurl.json [same options]
@main
struct Bench {
    struct Options {
        var bvid: String?
        var cookies: String?
        var playurl: String?
        var megabytes = 16
        var mode = NodeMode.overseas
        var quality = 80
        var codec = VideoCodec.hevc
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: ripper-bench (--bv BV… | --playurl file.json) [--cookies file] [--mb 16] [--mode overseas|mainland] [--quality 80] [--codec hevc|av1|avc]" }
    }

    static func main() async {
        do {
            try await run(parse(Array(CommandLine.arguments.dropFirst())))
        } catch {
            // URLError descriptions carry the failing signed URL.
            FileHandle.standardError.write(Data("error: \(Redactor.text(String(describing: error)))\n".utf8))
            exit(1)
        }
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            guard let value = iterator.next() else { throw UsageError() }
            switch flag {
            case "--bv": options.bvid = value
            case "--cookies": options.cookies = value
            case "--playurl": options.playurl = value
            case "--mb": options.megabytes = Int(value) ?? 16
            case "--mode": options.mode = value == "mainland" ? .mainland : .overseas
            case "--quality": options.quality = Int(value) ?? 80
            case "--codec": options.codec = VideoCodec(rawValue: value) ?? .hevc
            default: throw UsageError()
            }
        }
        guard options.bvid != nil || options.playurl != nil else { throw UsageError() }
        return options
    }

    static func loadPlayURL(_ options: Options) async throws -> PlayURLInfo {
        if let path = options.playurl {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let envelope = try JSONDecoder().decode(BiliEnvelope<PlayURLInfo>.self, from: data)
            guard let info = envelope.data else { throw BiliError.api(code: envelope.code, message: envelope.message ?? "") }
            return info
        }
        guard let bvid = options.bvid else { throw UsageError() }
        // The cookie file holds one Cookie header line; its values are never printed.
        let header = options.cookies.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        let client = BiliClient(transport: URLSessionHTTPTransport(),
                                cookies: CookieJar(CookieJar.parse(header: header.trimmingCharacters(in: .whitespacesAndNewlines))))
        try await client.ensureRiskCookies()
        let view = try await client.view(bvid: bvid)
        guard let page = view.pages.first else { throw BiliError.invalidLink }
        print("\(view.title) (cid \(page.cid))")
        return try await client.playURL(bvid: view.bvid, cid: page.cid, quality: options.quality)
    }

    static func run(_ options: Options) async throws {
        let info = try await loadPlayURL(options)
        guard let dash = info.dash,
              let choice = TrackSelector.choose(dash, quality: options.quality, codecOrder: [options.codec, .hevc, .avc, .av1]) else {
            throw BiliError.notDash
        }
        let video = choice.video
        print("video \(video.id) \(video.codecs) \(video.width)x\(video.height) \(video.bandwidth / 1000) kbps on \(NodeCatalog.nodeKey(of: video.baseURL))")
        let target = Int64(options.megabytes) << 20

        let singleStart = Date()
        let singleRange = ByteRange(start: video.indexRange.end + 1, end: video.indexRange.end + target)!
        // Each run gets its own URLSession so neither starts with the other's warm connections.
        let response = try await URLSessionRangeTransport(headers: BiliClient.mediaHeaders)
            .fetch(URL(string: video.baseURL)!, range: singleRange)
        var singleBytes: Int64 = 0
        if response.status == 206 {
            for try await chunk in response.body { singleBytes += Int64(chunk.count) }
        }
        let singleSeconds = Date().timeIntervalSince(singleStart)

        let session = RipperSession(sources: [.video: (video.baseURL, video.backupURLs)], mode: options.mode,
                                    transport: URLSessionRangeTransport(headers: BiliClient.mediaHeaders), auto: AutoConcurrency())
        let rippedStart = Date()
        let headers = try await session.loadHeaders(.video, through: video.indexRange.end)
        guard let segments = SidxParser.parse(headers.bytes, absoluteStart: 0) else { throw BiliError.decoding("no sidx") }
        session.setSegments(.video, segments)
        var rippedBytes: Int64 = 0
        for segment in segments where rippedBytes < target {
            for try await chunk in session.read(.video, segment.range) { rippedBytes += Int64(chunk.count) }
            session.updatePlayhead(seconds: segment.startTime, rate: 1)
        }
        let rippedSeconds = Date().timeIntervalSince(rippedStart)
        let stats = session.stats()
        session.close()

        func rate(_ bytes: Int64, _ seconds: Double) -> String {
            String(format: "%.2f MB/s", Double(bytes) / 1_048_576 / max(seconds, 0.001))
        }
        print("one connection: \(singleBytes) bytes in \(String(format: "%.2f", singleSeconds)) s = \(rate(singleBytes, singleSeconds)) (HTTP \(response.status))")
        print("ripper:         \(rippedBytes) bytes in \(String(format: "%.2f", rippedSeconds)) s = \(rate(rippedBytes, rippedSeconds))")
        print("connections \(stats.concurrency), requests \(stats.requests), failures \(stats.failures), duplicate \(String(format: "%.1f", stats.duplicateShare * 100))%")
        for node in stats.nodes {
            let state = stats.nodeStates.first { $0.node == node.node }
            print("  \(node.node): \(node.requests) req, \(node.failures) failed, first byte \(Int(node.firstByteMs)) ms, \(state.map { rate(Int64($0.bps), 1) } ?? "-") per connection, \(state?.state ?? "-")")
        }
    }
}
