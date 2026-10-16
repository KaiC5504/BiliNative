import Foundation
import BiliShared
import BiliAPI
import DashHLS
import DevLog
import Ripper

/// Downloads the start of a real video twice, over one connection and through Ripper, and prints both.
/// Usage: ripper-bench --bv BV1xxxxxxxxx [--cookies path] [--mb 16] [--mode overseas|mainland] [--quality 80] [--codec hevc|av1|avc]
///        ripper-bench --playurl saved-playurl.json [same options]
/// With --seeks N it times N cold 4 MiB reads at seeded random offsets instead of the throughput comparison;
/// --no-hurry turns hurry mode off for that run (and for the Ripper half of the comparison).
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
        var seeks = 0
        var hurry = true
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: ripper-bench (--bv BV… | --playurl file.json) [--cookies file] [--mb 16] [--mode overseas|mainland] [--quality 80] [--codec hevc|av1|avc] [--seeks N] [--no-hurry]" }
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
            if flag == "--no-hurry" {
                options.hurry = false
                continue
            }
            guard let value = iterator.next() else { throw UsageError() }
            switch flag {
            case "--bv": options.bvid = value
            case "--cookies": options.cookies = value
            case "--playurl": options.playurl = value
            case "--mb": options.megabytes = Int(value) ?? 16
            case "--mode": options.mode = value == "mainland" ? .mainland : .overseas
            case "--quality": options.quality = Int(value) ?? 80
            case "--codec": options.codec = VideoCodec(rawValue: value) ?? .hevc
            case "--seeks":
                guard let count = Int(value), count > 0 else { throw UsageError() }
                options.seeks = count
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

    /// The first of the primary and backup URLs that answers a small probe with 206; some accounts get 403
    /// from the primary node while a backup works. Probed on a throwaway session so the timed run starts cold.
    static func baselineURL(_ video: DashStream) async -> (url: String, label: String)? {
        let probe = URLSessionRangeTransport(headers: BiliClient.mediaHeaders)
        for (index, candidate) in ([video.baseURL] + video.backupURLs).enumerated() {
            let label = index == 0 ? "primary" : "backup \(index)"
            let node = NodeCatalog.nodeKey(of: candidate)
            guard let url = URL(string: candidate) else { continue }
            do {
                let answer = try await probe.fetch(url, range: ByteRange(start: 0, end: 1_023)!)
                if answer.status == 206 {
                    for try await _ in answer.body {}
                    return (candidate, label)
                }
                print("baseline probe: \(label) on \(node) answered HTTP \(answer.status)")
            } catch {
                print("baseline probe: \(label) on \(node) failed: \(Redactor.text(String(describing: error)))")
            }
        }
        return nil
    }

    static func makeSession(_ options: Options, video: DashStream) -> RipperSession {
        var config = RipperConfig()
        config.hurry = options.hurry
        return RipperSession(sources: [.video: (video.baseURL, video.backupURLs)], mode: options.mode, config: config,
                             transport: URLSessionRangeTransport(headers: BiliClient.mediaHeaders), auto: AutoConcurrency())
    }

    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Reads 4 MiB at seeded random offsets, each through a new session so every read starts cold, the way a
    /// seek into unloaded video does. The offset snaps back to its segment start because the player asks for
    /// segments; the playhead is put there too, so the read is due immediately.
    static func coldSeeks(_ options: Options, video: DashStream) async throws {
        let probe = makeSession(options, video: video)
        let headers: TrackHeaders
        do {
            headers = try await probe.loadHeaders(.video, through: video.indexRange.end)
        } catch {
            probe.close()
            throw error
        }
        probe.close()
        guard let segments = SidxParser.parse(headers.bytes, absoluteStart: 0), !segments.isEmpty else { throw BiliError.decoding("no sidx") }
        let total = headers.totalSize
        let wanted: Int64 = 4 << 20
        let low = total / 20
        let high = total - (2 << 20)
        guard high > low else { throw BiliError.decoding("video too small for cold seeks") }

        func mib(_ bytes: Int64) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }
        print("cold seeks: \(options.seeks) x \(mib(wanted)) MiB, seed 17, hurry \(options.hurry ? "on" : "off"), "
              + "offsets \(mib(low))-\(mib(high)) MiB of \(mib(total))")

        var generator = SeededGenerator(state: 17)
        var firstMiB: [Double] = []
        var whole: [Double] = []
        for number in 1...options.seeks {
            let offset = Int64.random(in: low...high, using: &generator)
            let segment = segments.last { $0.range.start <= offset } ?? segments[0]
            let start = segment.range.start
            let range = ByteRange(start: start, end: min(start + wanted, total) - 1)!
            let label = "seek \(number)/\(options.seeks) at \(mib(start)) MiB"
            let session = makeSession(options, video: video)
            do {
                _ = try await session.loadHeaders(.video, through: video.indexRange.end)
                session.setSegments(.video, segments)
                session.updatePlayhead(seconds: segment.startTime, rate: 1)
                let began = Date()
                var bytes: Int64 = 0
                var toFirstMiB: Double?
                for try await chunk in session.read(.video, range) {
                    bytes += Int64(chunk.count)
                    if toFirstMiB == nil && bytes >= 1 << 20 { toFirstMiB = Date().timeIntervalSince(began) }
                }
                let elapsed = Date().timeIntervalSince(began)
                let stats = session.stats()
                session.close()
                guard bytes == range.length, let toFirstMiB else {
                    print("\(label): short read, \(bytes) of \(range.length) bytes after \(String(format: "%.2f", elapsed)) s")
                    continue
                }
                firstMiB.append(toFirstMiB)
                whole.append(elapsed)
                print("\(label): first MiB \(String(format: "%.2f", toFirstMiB)) s, \(mib(bytes)) MiB \(String(format: "%.2f", elapsed)) s "
                      + "(connections \(stats.concurrency), requests \(stats.requests), failures \(stats.failures), "
                      + "duplicate \(String(format: "%.1f", stats.duplicateShare * 100))%)")
            } catch {
                session.close()
                print("\(label): failed: \(Redactor.text(String(describing: error)))")
            }
        }
        guard let firstMedian = median(firstMiB), let wholeMedian = median(whole) else {
            print("no seek finished")
            return
        }
        print("median first MiB: \(String(format: "%.2f", firstMedian)) s over \(firstMiB.count) of \(options.seeks) seeks")
        print("median \(mib(wanted)) MiB: \(String(format: "%.2f", wholeMedian)) s over \(whole.count) of \(options.seeks) seeks")
    }

    static func run(_ options: Options) async throws {
        let info = try await loadPlayURL(options)
        guard let dash = info.dash,
              let choice = TrackSelector.choose(dash, quality: options.quality, codecOrder: [options.codec, .hevc, .avc, .av1]) else {
            throw BiliError.notDash
        }
        let video = choice.video
        print("video \(video.id) \(video.codecs) \(video.width)x\(video.height) \(video.bandwidth / 1000) kbps on \(NodeCatalog.nodeKey(of: video.baseURL))")
        if options.seeks > 0 {
            try await coldSeeks(options, video: video)
            return
        }
        let target = Int64(options.megabytes) << 20

        let singleRange = ByteRange(start: video.indexRange.end + 1, end: video.indexRange.end + target)!
        var singleBytes: Int64 = 0
        var singleStatus = 0
        var singleSeconds = 0.0
        var singleSource = "no URL answered 206"
        var singleCut: String?
        if let chosen = await baselineURL(video) {
            singleSource = "\(chosen.label) on \(NodeCatalog.nodeKey(of: chosen.url))"
            // Each run gets its own URLSession so neither starts with the other's warm connections.
            let singleStart = Date()
            let response = try await URLSessionRangeTransport(headers: BiliClient.mediaHeaders)
                .fetch(URL(string: chosen.url)!, range: singleRange)
            singleStatus = response.status
            if response.status == 206 {
                // Some nodes close a long single response early; report that and still run Ripper.
                do {
                    for try await chunk in response.body { singleBytes += Int64(chunk.count) }
                } catch {
                    singleCut = Redactor.text(String(describing: error))
                }
            }
            singleSeconds = Date().timeIntervalSince(singleStart)
        }

        let session = makeSession(options, video: video)
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
        print("one connection: \(singleBytes) bytes in \(String(format: "%.2f", singleSeconds)) s = \(rate(singleBytes, singleSeconds)) (HTTP \(singleStatus), \(singleSource))"
              + (singleCut.map { " (truncated after \(singleBytes) bytes: \($0.prefix(160)); rate is up to the cut, not comparable)" } ?? ""))
        print("ripper:         \(rippedBytes) bytes in \(String(format: "%.2f", rippedSeconds)) s = \(rate(rippedBytes, rippedSeconds))")
        print("connections \(stats.concurrency), requests \(stats.requests), failures \(stats.failures), duplicate \(String(format: "%.1f", stats.duplicateShare * 100))%")
        for node in stats.nodes {
            // One entry per address on the node (e.g. a refused os=cosovbv next to a serving os=akam): show the best.
            let states = stats.nodeStates.filter { $0.node == node.node }
            let best = Resolver.NodeStatus.best(of: node.node, in: states)
            let all = states.count > 1 ? " (addresses: \(states.map(\.state).joined(separator: ", ")))" : ""
            print("  \(node.node): \(node.requests) req, \(node.failures) failed, first byte \(Int(node.firstByteMs)) ms, \(best.map { rate(Int64($0.bps), 1) } ?? "-") per connection, \(best?.state ?? "-")\(all)")
        }
    }
}
