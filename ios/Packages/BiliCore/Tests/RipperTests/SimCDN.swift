import Foundation
import BiliShared
import DevLog
@testable import Ripper

/// Serves one byte pattern on every node; each node (by host[:port]) can be made slow, broken or refusing.
final class SimCDN: RangeTransport, @unchecked Sendable {
    struct Behavior: Sendable {
        var firstByteMs: Double = 2
        var bytesPerSecond: Double = 200_000_000
        var status = 206
        /// Throw connection errors until this long after the SimCDN was created.
        var failForMs: Double = 0
        var truncateAfter: Int64?
        var stallAfter: Int64?
        var wrongRange = false
        /// A 206 without a Content-Range header.
        var omitContentRange = false
        /// Send this many bytes past the requested end while still claiming the requested range.
        var extraBytes: Int64 = 0
        /// The total the Content-Range advertises, when it should differ from the content size.
        var totalSize: Int64? = nil
        /// The first this many requests the node serves take `coldFirstByteMs` to the first byte, as on a CDN
        /// edge that does not have the file cached yet.
        var coldRequests = 0
        var coldFirstByteMs: Double = 0
        /// From this request on (counting from 1, per node) the first byte takes `coldFirstByteMs`, as when a
        /// node is busy sending other pieces and queues new requests behind them.
        var lateFirstByteFromRequest: Int?
        /// Answer 403 at once, as an edge refusal does, to addresses whose query contains one of these.
        var refusedQueries: [String] = []
        /// Bytes this node's copy lacks, as Akamai's copy of one file lacked 109972 through the end of its first
        /// MiB on 2026-10-16: a request starting inside gets no response, one running into it is cut off there.
        var missing: ClosedRange<Int64>?
        /// A request starting inside this span waits `coldRangeFirstByteMs` for its first byte and then runs at
        /// `coldRangeBytesPerSecond`, as an edge does over a part of the file it has not served lately.
        var coldRange: ClosedRange<Int64>?
        var coldRangeFirstByteMs: Double = 0
        var coldRangeBytesPerSecond: Double?
    }

    struct ConnectionLost: Error {}

    let content: [UInt8]
    private let behaviors: Locked<[String: Behavior]>
    let requests = Locked<[String]>([])
    /// Bytes of responses sent to the end, per full URL; copies cancelled midway are not counted.
    let deliveredBytes = Locked<[String: Int64]>([:])
    private let born = ProcessInfo.processInfo.systemUptime
    private let servedRequests = Locked<[String: Int]>([:])

    init(size: Int, behaviors: [String: Behavior] = [:]) {
        content = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        self.behaviors = Locked(behaviors)
    }

    func set(_ node: String, _ behavior: Behavior) {
        behaviors.withLock { $0[node] = behavior }
    }

    func requestCount() -> Int { requests.current.count }

    func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
        let node = NodeCatalog.nodeKey(of: url.absoluteString)
        requests.withLock { $0.append(node) }
        let behavior = behaviors.current[node] ?? Behavior()
        let empty = AsyncThrowingStream<[UInt8], Error> { $0.finish() }
        let query = url.query ?? ""
        if behavior.refusedQueries.contains(where: query.contains) {
            try await sleepMs(2)
            return TransportResponse(status: 403, headers: [:], body: empty)
        }
        let cold = servedRequests.withLock { map -> Bool in
            let number = map[node, default: 0] + 1
            map[node] = number
            return number <= behavior.coldRequests || number >= (behavior.lateFirstByteFromRequest ?? Int.max)
        }
        let coldSpan = behavior.coldRange?.contains(range.start) ?? false
        try await sleepMs(coldSpan ? behavior.coldRangeFirstByteMs : cold ? behavior.coldFirstByteMs : behavior.firstByteMs)
        let bytesPerSecond = coldSpan ? behavior.coldRangeBytesPerSecond ?? behavior.bytesPerSecond : behavior.bytesPerSecond
        if (ProcessInfo.processInfo.systemUptime - born) * 1000 < behavior.failForMs { throw ConnectionLost() }
        if behavior.status != 206 { return TransportResponse(status: behavior.status, headers: [:], body: empty) }
        guard range.end < Int64(content.count) else { return TransportResponse(status: 416, headers: [:], body: empty) }
        if let missing = behavior.missing, missing.contains(range.start) { throw ConnectionLost() }
        let served = behavior.wrongRange ? (ByteRange(start: range.start + 1, end: range.end) ?? range) : range
        let content = self.content
        let deliveredBytes = self.deliveredBytes
        let key = url.absoluteString
        let bodyEnd = min(Int64(content.count) - 1, served.end + behavior.extraBytes)
        let cutAt = behavior.missing.map(\.lowerBound).flatMap { $0 > served.start && $0 <= bodyEnd ? $0 : nil }
        let body = AsyncThrowingStream<[UInt8], Error> { continuation in
            let task = Task {
                var offset = served.start
                while offset <= bodyEnd, !Task.isCancelled {
                    let sent = offset - served.start
                    if let limit = behavior.truncateAfter, sent >= limit { break }
                    if let limit = behavior.stallAfter, sent >= limit {
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        break
                    }
                    var end = min(bodyEnd, offset + 16 * 1024 - 1)
                    // Cut chunks exactly at the truncation and stall points.
                    if let limit = behavior.truncateAfter { end = min(end, served.start + limit - 1) }
                    if let limit = behavior.stallAfter { end = min(end, served.start + limit - 1) }
                    if let cutAt {
                        if offset >= cutAt {
                            continuation.finish(throwing: ConnectionLost())
                            return
                        }
                        end = min(end, cutAt - 1)
                    }
                    continuation.yield(Array(content[Int(offset)...Int(end)]))
                    let ms = Double(end - offset + 1) / bytesPerSecond * 1000
                    if ms >= 1 { try? await sleepMs(ms) } else { await Task.yield() }
                    offset = end + 1
                }
                if offset > bodyEnd { deliveredBytes.withLock { $0[key, default: 0] += bodyEnd - served.start + 1 } }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        let total = behavior.totalSize ?? Int64(content.count)
        let headers = behavior.omitContentRange ? [:] : ["content-range": "bytes \(served.start)-\(served.end)/\(total)"]
        return TransportResponse(status: 206, headers: headers, body: body)
    }
}

enum TestEngine {
    static let primary = "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv"
    static let cosov = "upos-sz-mirrorcosov.bilivideo.com"
    static let aliov = "upos-sz-mirroraliov.bilivideo.com"
    static let hk1 = "cn-hk-eq-01-01.bilivideo.com"
    static let hk3 = "cn-hk-eq-01-03.bilivideo.com"

    static var config: RipperConfig {
        var config = RipperConfig()
        config.firstByteTimeoutMs = 300
        config.stallTimeoutMs = 300
        config.attemptTimeoutMs = 3_000
        config.hedgeDelayMs = 100
        config.retryWindowMs = 5_000
        config.fixedConcurrency = 8
        return config
    }

    /// Slow simulated nodes pause between chunks; leave room for that on a loaded runner.
    static var slowConfig: RipperConfig {
        var config = TestEngine.config
        config.stallTimeoutMs = 2_000
        return config
    }

    static func context(_ cdn: SimCDN, config: RipperConfig = TestEngine.config, auto: AutoConcurrency? = nil) -> EngineContext {
        EngineContext(transport: cdn, pool: ConnectionPool(limit: config.fixedConcurrency ?? auto?.threads ?? 8), config: config,
                      meter: Meter(), stats: EngineStats(), auto: auto, clock: .system, logger: Logger(session: "test"))
    }

    static func resolver() -> Resolver {
        Resolver(primary: primary, backups: [], mode: .overseas, bans: BanList())
    }
}
