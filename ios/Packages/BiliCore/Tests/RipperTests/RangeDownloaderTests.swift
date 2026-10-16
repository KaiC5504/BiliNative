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

    /// The overseas Akamai node of 2026-10-16: it refuses the primary `os=cosovbv` address at the edge and serves
    /// the `os=akam` backup, slow to start while cold and then far faster than every mirror. The mirrors serve both.
    func testAddressRefusedOnTheFastestNodeDropsOnlyThatPair() async throws {
        let akamai = "upos-hz-mirrorakam.akamaized.net"
        let address = "https://\(akamai)/upgcxcode/1/2/3/v.m4s?deadline=9"
        let refused = address + "&os=cosovbv"
        let served = address + "&os=akam"
        var behaviors: [String: SimCDN.Behavior] = [
            akamai: .init(firstByteMs: 20, bytesPerSecond: 40_000_000, coldRequests: 2, coldFirstByteMs: 400, refusedQueries: ["os=cosovbv"]),
        ]
        for node in NodeCatalog.overseas { behaviors[node] = .init(firstByteMs: 5, bytesPerSecond: 400_000) }
        let cdn = SimCDN(size: 6_500_000, behaviors: behaviors)
        var config = TestEngine.slowConfig
        config.firstByteTimeoutMs = 1_000
        let clock = ManualClock(1_000_000)
        let bans = BanList()
        let resolver = Resolver(primary: refused, backups: [served], mode: .overseas, bans: bans, clock: clock.clock)
        let downloader = RangeDownloader(ctx: TestEngine.context(cdn, config: config))
        _ = try await downloader.meta(ByteRange(start: 0, end: 1_023)!, resolver: resolver)
        // Unproven, the Akamai node gets work only after the four warm-up ranges (BTR's exploration order).
        for index in Int64(0)..<12 {
            // Playback time passes between segments, so the refused address's backoff runs out.
            clock.advance(7_000)
            let range = ByteRange(start: 1_024 + index << 19, end: 1_023 + (index + 1) << 19)!
            var bytes: [UInt8] = []
            for try await chunk in downloader.stream(range, resolver: resolver, startup: index == 0, priority: 50, deadline: nil) {
                bytes += chunk
            }
            XCTAssertEqual(bytes, Array(cdn.content[Int(range.start)...Int(range.end)]))
        }
        XCTAssertTrue(bans.allowsNode(served), "a refusal of one address must not ban the node")
        XCTAssertTrue(resolver.allows(served))
        XCTAssertFalse(bans.allows(refused), "the refusing node and address pair is dropped")
        XCTAssertTrue(bans.allowsAddress(refused), "the mirrors serve that address")
        var sent: [String: Int64] = [:]
        for (url, bytes) in cdn.deliveredBytes.current { sent[NodeCatalog.nodeKey(of: url), default: 0] += bytes }
        let mirrorMost = sent.filter { $0.key != akamai }.values.max() ?? 0
        XCTAssertGreaterThan(sent[akamai] ?? 0, mirrorMost, "the fastest node carries the most bytes: \(sent)")
    }

    /// Akamai's copy of KaiC's q80 file, 2026-10-16: bytes 109972 through the end of the first MiB were missing,
    /// the rest was whole and far faster than any mirror.
    func testNodeWithADamagedSpanKeepsServingTheRest() async throws {
        let missing = Int64(109_972)...Int64(1_048_575)
        var behaviors: [String: SimCDN.Behavior] = [TestEngine.aliov: .init(firstByteMs: 20, bytesPerSecond: 40_000_000, missing: missing)]
        for node in [TestEngine.cosov, TestEngine.hk1, TestEngine.hk3] { behaviors[node] = .init(bytesPerSecond: 1_000_000) }
        let cdn = SimCDN(size: 6_500_000, behaviors: behaviors)
        let transport = RecordingTransport(cdn)
        let resolver = TestEngine.resolver()
        let downloader = RangeDownloader(ctx: context(transport, config: TestEngine.slowConfig))
        func read(_ index: Int64) async throws {
            let range = ByteRange(start: 1_024 + index << 19, end: 1_023 + (index + 1) << 19)!
            var bytes: [UInt8] = []
            for try await chunk in downloader.stream(range, resolver: resolver, startup: index == 0, priority: 50, deadline: nil) {
                bytes += chunk
            }
            XCTAssertEqual(bytes, Array(cdn.content[Int(range.start)...Int(range.end)]))
        }
        _ = try await downloader.meta(ByteRange(start: 0, end: 1_023)!, resolver: resolver)
        for index in Int64(0)..<12 { try await read(index) }
        let aliovURL = url(on: TestEngine.aliov)
        XCTAssertTrue(resolver.bans?.allowsNode(aliovURL) ?? false)
        XCTAssertTrue(resolver.allows(aliovURL))
        let sent = cdn.deliveredBytes.current
        let total = sent.values.reduce(0, +)
        XCTAssertGreaterThan(sent[aliovURL] ?? 0, total / 2, "the fast node carries most bytes: \(sent)")

        // Seeking back: the damaged span is not asked of that node again.
        let asked = transport.requests.current.count
        for index in Int64(0)..<2 { try await read(index) }
        let again = transport.requests.current.dropFirst(asked)
            .filter { $0.node == TestEngine.aliov && $0.range.end >= missing.lowerBound && $0.range.start <= missing.upperBound }
        XCTAssertEqual(again.count, 0, "\(again.map(\.range))")
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

    func testMismatchedPieceIsNeverYielded() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(totalSize: 2_000_001)])
        let transport = RecordingTransport(cdn)
        var config = TestEngine.config
        // No backup copies: every piece is served by the node it was assigned to.
        config.hedgeDelayMs = 60_000
        let downloader = RangeDownloader(ctx: context(transport, config: config))
        var yielded: Int64 = 0
        do {
            for try await chunk in downloader.stream(mebibyte, resolver: TestEngine.resolver(), startup: false, priority: 50, deadline: nil,
                                                     expectedTotal: 2_000_000) {
                yielded += Int64(chunk.count)
            }
            XCTFail("expected totalMismatch")
        } catch {
            XCTAssertEqual(error as? RipperError, .totalMismatch)
        }
        let firstLie = transport.requests.current.filter { $0.node == TestEngine.cosov }.map(\.range.start).min()
        XCTAssertNotNil(firstLie)
        XCTAssertLessThanOrEqual(yielded, firstLie ?? 0, "no byte from the mismatched piece or after it")
    }

    func testStartupHeadIsCheckedAgainstTheExpectedTotal() async {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(totalSize: 2_000_001) }
        let downloader = RangeDownloader(ctx: TestEngine.context(SimCDN(size: 2_000_000, behaviors: behaviors)))
        var yielded = 0
        do {
            for try await chunk in downloader.stream(mebibyte, resolver: TestEngine.resolver(), startup: true, priority: 50, deadline: nil,
                                                     expectedTotal: 2_000_000) {
                yielded += chunk.count
            }
            XCTFail("expected totalMismatch")
        } catch {
            XCTAssertEqual(error as? RipperError, .totalMismatch)
        }
        XCTAssertEqual(yielded, 0)
    }

    func testHedgeDueRules() {
        let clock = ManualClock()
        func downloader(usualBps: Double) -> PieceDownloader {
            let meter = Meter()
            if usualBps > 0 { meter.record(bytes: Int64(usualBps), elapsedMs: 1_000) }
            return PieceDownloader(ctx: EngineContext(transport: SimCDN(size: 1), pool: ConnectionPool(limit: 1), config: TestEngine.config,
                                                      meter: meter, stats: EngineStats(), auto: nil, clock: clock.clock,
                                                      logger: Logger(session: "test")))
        }
        func copy(received: Int) -> AttemptProgress {
            let progress = AttemptProgress()
            clock.set(0)
            progress.begin(at: 0, length: 1_000_000, base: Prefix())
            if received > 0 { progress.append([UInt8](repeating: 0, count: received), at: 0) }
            return progress
        }
        let unknownUsual = downloader(usualBps: 0)

        let silent = copy(received: 0)
        clock.set(100)
        XCTAssertFalse(unknownUsual.hedgeDue(first: silent, delayMs: 250, deadlineAt: 60_000, copyBps: 0), "before the delay")
        clock.set(300)
        XCTAssertTrue(unknownUsual.hedgeDue(first: silent, delayMs: 250, deadlineAt: 60_000, copyBps: 0), "no bytes after the delay")

        let stuck = copy(received: 100_000)
        clock.set(100)
        _ = unknownUsual.hedgeDue(first: stuck, delayMs: 250, deadlineAt: 60_000, copyBps: 0)
        clock.set(400)
        XCTAssertTrue(unknownUsual.hedgeDue(first: stuck, delayMs: 250, deadlineAt: 60_000, copyBps: 0), "no progress for a whole delay")

        // 500,000 of 1,000,000 bytes in 300 ms: done at 600 ms.
        func onPace(_ pieces: PieceDownloader, deadlineAt: Double, copyBps: Double) -> Bool {
            let progress = copy(received: 500_000)
            clock.set(300)
            return pieces.hedgeDue(first: progress, delayMs: 250, deadlineAt: deadlineAt, copyBps: copyBps)
        }
        XCTAssertFalse(onPace(unknownUsual, deadlineAt: 2_200, copyBps: 10_000_000), "on pace with 1.5 s to spare")
        XCTAssertTrue(onPace(unknownUsual, deadlineAt: 1_000, copyBps: 4_000_000), "the copy's node is over 1.5x faster")
        XCTAssertTrue(onPace(downloader(usualBps: 10_000_000), deadlineAt: 1_000, copyBps: 2_000_000), "under 0.6x the usual connection")
        XCTAssertFalse(onPace(downloader(usualBps: 2_000_000), deadlineAt: 1_000, copyBps: 2_000_000), "the copy's node is no faster")
        XCTAssertTrue(onPace(downloader(usualBps: 2_000_000), deadlineAt: 1_000, copyBps: 0), "an unmeasured node is worth a try")
    }

    func testFiniteDeadlineHedgesASlowFirstByte() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 2_000)])
        var config = TestEngine.config
        // Only a backup copy, not the first-byte timeout, can rescue cosov's pieces.
        config.firstByteTimeoutMs = 5_000
        let deadlineAt = MonotonicClock.system.nowMs() + 10_000
        let started = Date()
        var bytes: [UInt8] = []
        for try await chunk in RangeDownloader(ctx: TestEngine.context(cdn, config: config))
            .stream(mebibyte, resolver: TestEngine.resolver(), startup: false, priority: 50, deadline: { deadlineAt }) {
            bytes += chunk
        }
        XCTAssertEqual(bytes, Array(cdn.content[0...1_048_575]))
        XCTAssertTrue(cdn.requests.current.contains(TestEngine.cosov))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "cosov's pieces are hedged, not waited out")
    }

    func testCancellingTheConsumerStopsAllWork() async throws {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(bytesPerSecond: 250_000) }
        let cdn = SimCDN(size: 2_000_000, behaviors: behaviors)
        let ctx = TestEngine.context(cdn, config: TestEngine.slowConfig)
        let downloader = RangeDownloader(ctx: ctx)
        let received = Locked<Int64>(0)
        // Startup mode yields the 64 KiB head long before the rest of the range is in.
        let consumer = Task {
            for try await chunk in downloader.stream(mebibyte, resolver: TestEngine.resolver(), startup: true, priority: 50, deadline: nil) {
                received.withLock { $0 += Int64(chunk.count) }
            }
        }
        let waitStarted = Date()
        while received.current == 0 && Date().timeIntervalSince(waitStarted) < 5 { try await sleepMs(5) }
        consumer.cancel()
        _ = try? await consumer.value
        XCTAssertGreaterThan(received.current, 0)
        XCTAssertLessThan(received.current, mebibyte.length)

        let idleStarted = Date()
        while ctx.pool.active > 0 && Date().timeIntervalSince(idleStarted) < 3 { try await sleepMs(10) }
        XCTAssertEqual(ctx.pool.active, 0)
        XCTAssertEqual(ctx.pool.queued, 0)
        let asked = cdn.requestCount()
        try await sleepMs(500)
        XCTAssertEqual(cdn.requestCount(), asked, "no new requests once the consumer is gone")
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

    /// cosov is sending its first piece slowly, so its later requests wait behind it and miss the first-byte
    /// timeout. That is the node being busy, not silent: it must not be banned.
    func slowBusyCosov(size: Int, bytesPerSecond: Double) -> SimCDN {
        SimCDN(size: size, behaviors: [TestEngine.cosov: .init(bytesPerSecond: bytesPerSecond, coldFirstByteMs: 2_500, lateFirstByteFromRequest: 2)])
    }

    func testSilentRequestsToABusyNodeDoNotBanIt() async throws {
        let cdn = slowBusyCosov(size: 5_000_000, bytesPerSecond: 220_000)
        // Not Resolver's default list: the first piece of cosov finishing heals its strikes, so only the
        // ban event itself shows that the node was ever banned.
        let bans = BanList()
        let banned = Locked<[String]>([])
        bans.onBan = { node, _, _ in banned.withLock { $0.append(node) } }
        let resolver = Resolver(primary: TestEngine.primary, backups: [], mode: .overseas, bans: bans)
        var config = TestEngine.slowConfig
        config.hedgeDelayMs = 5_000
        config.fixedConcurrency = 16
        let range = ByteRange(start: 0, end: 4 * 1_048_576 - 1)!
        let bytes = try await collect(cdn, range: range, resolver: resolver, config: config)
        XCTAssertEqual(bytes, Array(cdn.content[0...Int(range.end)]))
        let cosovRequests = cdn.requests.current.filter { $0 == TestEngine.cosov }.count
        XCTAssertGreaterThanOrEqual(cosovRequests, 2, "the test needs requests that wait behind the first one")
        XCTAssertEqual(banned.current, [], "a node that is sending other pieces was banned")
    }

    func testABusyNodeThatNeverAnswersNewRequestsStillLetsTheRangeFinish() async throws {
        let cdn = slowBusyCosov(size: 9_000_000, bytesPerSecond: 1_600_000)
        var config = TestEngine.slowConfig
        config.hedgeDelayMs = 5_000
        let ctx = TestEngine.context(cdn, config: config)
        let cosovURL = url(on: TestEngine.cosov)
        let sawFull = Locked(false)
        let watcher = Task {
            while !Task.isCancelled {
                if ctx.nodes.isFull(cosovURL) { sawFull.withLock { $0 = true } }
                try? await sleepMs(10)
            }
        }
        defer { watcher.cancel() }
        let range = ByteRange(start: 0, end: 8 * 1_048_576 - 1)!
        let started = Date()
        var bytes: [UInt8] = []
        for try await chunk in RangeDownloader(ctx: ctx).stream(range, resolver: TestEngine.resolver(), startup: false, priority: 50, deadline: nil) {
            bytes += chunk
        }
        XCTAssertEqual(bytes, Array(cdn.content[0...Int(range.end)]))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "cosov's own piece takes about 1 s")
        XCTAssertTrue(sawFull.current, "cosov is capped at the one piece it was sending")
    }
}
