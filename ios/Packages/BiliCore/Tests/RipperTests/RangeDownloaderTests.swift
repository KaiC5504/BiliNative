import XCTest
import BiliShared
import DevLog
@testable import Ripper

/// Records every request on its way to the simulated CDN.
final class RecordingTransport: RangeTransport, @unchecked Sendable {
    let cdn: SimCDN
    let requests = Locked<[(node: String, range: ByteRange)]>([])

    init(_ cdn: SimCDN) {
        self.cdn = cdn
    }

    func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
        requests.withLock { $0.append((NodeCatalog.nodeKey(of: url.absoluteString), range)) }
        return try await cdn.fetch(url, range: range)
    }
}

final class RangeDownloaderTests: XCTestCase {
    let mebibyte = ByteRange(start: 0, end: 1_048_575)!

    func collect(_ cdn: SimCDN, range: ByteRange, resolver: Resolver = TestEngine.resolver(), startup: Bool = false,
                 auto: AutoConcurrency? = nil, config: RipperConfig = TestEngine.config) async throws -> [UInt8] {
        let downloader = RangeDownloader(ctx: TestEngine.context(cdn, config: config, auto: auto))
        var bytes: [UInt8] = []
        for try await chunk in downloader.stream(range, resolver: resolver, startup: startup, priority: 50, deadline: nil) {
            bytes += chunk
        }
        return bytes
    }

    func context(_ transport: RangeTransport, config: RipperConfig = TestEngine.config) -> EngineContext {
        EngineContext(transport: transport, pool: ConnectionPool(limit: config.fixedConcurrency ?? 8), config: config, meter: Meter(),
                      stats: EngineStats(), auto: nil, clock: .system, logger: Logger(session: "test"))
    }

    func url(on node: String) -> String {
        TestEngine.primary.replacingOccurrences(of: "upos-sz-mirrorcos.bilivideo.com", with: node)
    }

    func testAllFastNodesDeliverExactBytesInOrder() async throws {
        let cdn = SimCDN(size: 2_000_000)
        let bytes = try await collect(cdn, range: mebibyte)
        XCTAssertEqual(bytes, Array(cdn.content[0...1_048_575]))
        XCTAssertGreaterThan(Set(cdn.requests.current).count, 1, "pieces should spread over several nodes")
    }

    func testStartupProbeThenPieces() async throws {
        let cdn = SimCDN(size: 2_000_000)
        let range = ByteRange(start: 1_000, end: 900_000)!
        let bytes = try await collect(cdn, range: range, startup: true)
        XCTAssertEqual(bytes, Array(cdn.content[1_000...900_000]))
    }

    func testRefusingNodeIsRoutedAroundAndBanned() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(status: 403)])
        let resolver = TestEngine.resolver()
        let bytes = try await collect(cdn, range: mebibyte, resolver: resolver)
        XCTAssertEqual(bytes, Array(cdn.content[0...1_048_575]))
        let cosovURL = TestEngine.primary.replacingOccurrences(of: "upos-sz-mirrorcos.bilivideo.com", with: TestEngine.cosov)
        XCTAssertFalse(resolver.allows(cosovURL))
    }

    func testBrokenNodesNeverCorruptTheOutput() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [
            TestEngine.cosov: .init(wrongRange: true),
            TestEngine.aliov: .init(truncateAfter: 10_000),
            TestEngine.hk1: .init(stallAfter: 16_384),
        ])
        let bytes = try await collect(cdn, range: mebibyte)
        XCTAssertEqual(bytes, Array(cdn.content[0...1_048_575]))
    }

    func testSlowFirstByteIsHedged() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 1_000)])
        let started = Date()
        let bytes = try await collect(cdn, range: mebibyte)
        XCTAssertEqual(bytes, Array(cdn.content[0...1_048_575]))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testEveryNodeRefusingFails() async {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(status: 403) }
        let cdn = SimCDN(size: 2_000_000, behaviors: behaviors)
        do {
            _ = try await collect(cdn, range: ByteRange(start: 0, end: 99_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertNotNil(error as? RipperError)
        }
    }

    /// Review focus 5: a Wi-Fi to cellular switch makes every node fail for a moment.
    func testShortNetworkBlipIsRiddenOut() async throws {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(failForMs: 400) }
        let cdn = SimCDN(size: 2_000_000, behaviors: behaviors)
        let bytes = try await collect(cdn, range: ByteRange(start: 0, end: 299_999)!)
        XCTAssertEqual(bytes, Array(cdn.content[0...299_999]))
    }

    func testRateLimitPushesConnectionsDown() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.aliov: .init(status: 429)])
        let auto = AutoConcurrency()
        auto.newSession()
        XCTAssertEqual(auto.threads, 16)
        var config = TestEngine.config
        config.fixedConcurrency = nil
        _ = try await collect(cdn, range: mebibyte, auto: auto, config: config)
        XCTAssertLessThan(auto.threads, 16)
    }

    func testMetaRaceReturnsTheWholeRange() async throws {
        let cdn = SimCDN(size: 50_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 200)])
        let downloader = RangeDownloader(ctx: TestEngine.context(cdn))
        let output = try await downloader.meta(ByteRange(start: 0, end: 4_999)!, resolver: TestEngine.resolver())
        XCTAssertEqual(output.bytes, Array(cdn.content[0..<5_000]))
        XCTAssertEqual(output.total, 50_000)
    }

    /// One round's walk over the nodes takes about 0.4 s on Windows, which can hide a 0.4 s blip by
    /// itself. This one is longer than a round but shorter than the 0.5 s + 1 s pauses before round 3.
    func testBlipIsRiddenOutByTheRetryRoundsAlone() async throws {
        func blip() -> SimCDN {
            var behaviors: [String: SimCDN.Behavior] = [:]
            for node in NodeCatalog.overseas { behaviors[node] = .init(failForMs: 1_400) }
            return SimCDN(size: 2_000_000, behaviors: behaviors)
        }
        let range = ByteRange(start: 0, end: 299_999)!
        var oneRound = TestEngine.config
        oneRound.pieceRounds = 1
        do {
            _ = try await collect(blip(), range: range, config: oneRound)
            XCTFail("a single round cannot outlast the blip")
        } catch {}

        let cdn = blip()
        let ctx = context(cdn)
        var bytes: [UInt8] = []
        for try await chunk in RangeDownloader(ctx: ctx).stream(range, resolver: TestEngine.resolver(), startup: false, priority: 50, deadline: nil) {
            bytes += chunk
        }
        XCTAssertEqual(bytes, Array(cdn.content[0...299_999]))
        XCTAssertGreaterThan(ctx.stats.snapshot().failures, 0, "the blip must have hit the first round")
    }

    func testFailsOnlyAfterEveryRound() async {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(status: 403) }
        let cdn = SimCDN(size: 2_000_000, behaviors: behaviors)
        let started = Date()
        do {
            _ = try await collect(cdn, range: ByteRange(start: 0, end: 99_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .badResponse(status: 403))
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 1.4, "rounds pause 0.5 s and 1 s")
        for node in NodeCatalog.overseas {
            XCTAssertGreaterThanOrEqual(cdn.requests.current.filter { $0 == node }.count, 3, "\(node) is asked in every round")
        }
    }

    func testBannedNodeGetsNoMoreWork() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(status: 403)])
        let resolver = TestEngine.resolver()
        _ = try await collect(cdn, range: mebibyte, resolver: resolver)
        XCTAssertFalse(resolver.allows(url(on: TestEngine.cosov)))
        let asked = cdn.requests.current.filter { $0 == TestEngine.cosov }.count
        let bytes = try await collect(cdn, range: ByteRange(start: 1_048_576, end: 1_999_999)!, resolver: resolver)
        XCTAssertEqual(bytes, Array(cdn.content[1_048_576...1_999_999]))
        XCTAssertEqual(cdn.requests.current.filter { $0 == TestEngine.cosov }.count, asked)
    }

    func testDifferentTotalSizesFailTheRange() async {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(totalSize: 2_000_001)])
        var config = TestEngine.config
        // No backup copies: with no speeds known, every node wins the pieces it was assigned.
        config.hedgeDelayMs = 60_000
        do {
            _ = try await collect(cdn, range: mebibyte, config: config)
            XCTFail("expected totalMismatch")
        } catch {
            XCTAssertEqual(error as? RipperError, .totalMismatch)
        }
        XCTAssertTrue(cdn.requests.current.contains(TestEngine.cosov))
    }

    func testUrgentRangeOvertakesQueuedWork() async throws {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(bytesPerSecond: 250_000) }
        let cdn = SimCDN(size: 4_000_000, behaviors: behaviors)
        let downloader = RangeDownloader(ctx: TestEngine.context(cdn, config: TestEngine.slowConfig))
        let resolver = TestEngine.resolver()
        let finished = Locked<[String]>([])
        func drain(_ name: String, _ range: ByteRange, priority: Double) -> Task<Void, Error> {
            Task {
                for try await _ in downloader.stream(range, resolver: resolver, startup: false, priority: priority, deadline: nil) {}
                finished.withLock { $0.append(name) }
            }
        }
        // Three 7-piece ranges queue more pieces than the 8 connections can run.
        let low = (0..<3).map { index in
            drain("low", ByteRange(start: Int64(index) * 458_752, end: Int64(index + 1) * 458_752 - 1)!, priority: 10)
        }
        try await sleepMs(30)
        let urgent = drain("urgent", ByteRange(start: 2_000_000, end: 2_458_751)!, priority: 50)
        for task in low + [urgent] { try await task.value }
        let order = finished.current
        XCTAssertLessThanOrEqual(order.firstIndex(of: "urgent") ?? 99, 1, "only a range already fully running may finish first: \(order)")
    }

    func testResumeOnlyFromAPrefixOfAtLeast32KiB() async throws {
        for (cut, resumedAt) in [(Int64(40_000), Int64(40_000)), (10_000, 0)] {
            let cdn = SimCDN(size: 300_000, behaviors: [TestEngine.cosov: .init(truncateAfter: cut)])
            let transport = RecordingTransport(cdn)
            var config = TestEngine.config
            // The backup copy starts only once the first fails.
            config.hedgeDelayMs = 60_000
            let output = try await PieceDownloader(ctx: context(transport, config: config)).download(
                piece: ByteRange(start: 0, end: 199_999)!, index: 0, resolver: TestEngine.resolver(),
                preferred: [url(on: TestEngine.cosov)], mode: .normal, priority: 50, deadline: nil)
            XCTAssertEqual(output.bytes, Array(cdn.content[0..<200_000]))
            let requests = transport.requests.current
            XCTAssertEqual(requests.first?.node, TestEngine.cosov)
            XCTAssertEqual(requests.dropFirst().first?.range, ByteRange(start: resumedAt, end: 199_999), "cut after \(cut)")
        }
    }

    func testResumeBasePrefersTheLongestValidPrefix() {
        func prefix(_ bytes: Int) -> Prefix { Prefix(bytes: Int64(bytes), chunks: [[UInt8](repeating: 1, count: bytes)]) }
        XCTAssertEqual(PieceDownloader.resumeBase(prefix: prefix(20_000), live: nil, pieceLength: 100_000).bytes, 0)
        XCTAssertEqual(PieceDownloader.resumeBase(prefix: prefix(40_000), live: nil, pieceLength: 100_000).bytes, 40_000)
        XCTAssertEqual(PieceDownloader.resumeBase(prefix: prefix(40_000), live: prefix(60_000), pieceLength: 100_000).bytes, 60_000)
        XCTAssertEqual(PieceDownloader.resumeBase(prefix: prefix(40_000), live: prefix(20_000), pieceLength: 100_000).bytes, 40_000)
        XCTAssertEqual(PieceDownloader.resumeBase(prefix: Prefix(), live: prefix(100_000), pieceLength: 100_000).bytes, 0)
    }

    func testLosingCopyIsCancelledAndSampledNotPunished() async throws {
        let cdn = SimCDN(size: 600_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 200_000)])
        let transport = RecordingTransport(cdn)
        var config = TestEngine.slowConfig
        config.hedgeDelayMs = 500
        let ctx = context(transport, config: config)
        let resolver = TestEngine.resolver()
        let cosovURL = url(on: TestEngine.cosov)
        let started = Date()
        let output = try await PieceDownloader(ctx: ctx).download(piece: ByteRange(start: 0, end: 399_999)!, index: 0, resolver: resolver,
                                                                  preferred: [cosovURL], mode: .normal, priority: 50, deadline: nil)
        XCTAssertEqual(output.bytes, Array(cdn.content[0..<400_000]))
        XCTAssertNotEqual(output.url, cosovURL)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "cosov alone needs 2 s")
        let backup = transport.requests.current.first { $0.node != TestEngine.cosov }
        XCTAssertGreaterThanOrEqual(backup?.range.start ?? 0, PieceDownloader.resumeMinBytes, "the backup resumes from the first copy's bytes")
        XCTAssertTrue(resolver.allows(cosovURL))
        XCTAssertEqual(ctx.stats.snapshot().failures, 0)
        XCTAssertGreaterThan(resolver.speed(cosovURL), 0, "the cancelled copy still measures its node")
    }
}
