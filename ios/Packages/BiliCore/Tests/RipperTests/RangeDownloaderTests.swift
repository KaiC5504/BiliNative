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

    func testLosingCopyMarksItsNodeSlow() async throws {
        let cdn = SimCDN(size: 600_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 200_000)])
        var config = TestEngine.slowConfig
        config.hedgeDelayMs = 500
        let ctx = context(RecordingTransport(cdn), config: config)
        let cosovURL = url(on: TestEngine.cosov)
        ctx.nodes.begin(cosovURL); ctx.nodes.firstByte(cosovURL, ms: 5)
        ctx.nodes.body(cosovURL, bytes: 4_000_000, ms: 1_000); ctx.nodes.end(cosovURL, receiving: true)
        let output = try await PieceDownloader(ctx: ctx).download(piece: ByteRange(start: 0, end: 399_999)!, index: 0, resolver: TestEngine.resolver(),
                                                                  preferred: [cosovURL], mode: .normal, priority: 50, deadline: nil)
        XCTAssertNotEqual(output.url, cosovURL)
        XCTAssertLessThan(ctx.nodes.bps(cosovURL), 4_000_000, "cosov was still sending when the other copy won")
        XCTAssertEqual(ctx.nodes.inflight(cosovURL), 0)
    }

    func testPieceEventNamesTheCopyOnlyForCopiesAfterTheFirst() async throws {
        let cdn = SimCDN(size: 600_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 200_000)])
        var config = TestEngine.slowConfig
        config.hedgeDelayMs = 500
        let ctx = context(RecordingTransport(cdn), config: config)
        let sink = MemorySink()
        ctx.logger.add(sink)
        let cosovURL = url(on: TestEngine.cosov)
        _ = try await PieceDownloader(ctx: ctx).download(piece: ByteRange(start: 0, end: 399_999)!, index: 0, resolver: TestEngine.resolver(),
                                                         preferred: [cosovURL], mode: .normal, priority: 50, deadline: nil)
        let pieces = sink.events.filter { $0.msg == "piece" }
        XCTAssertEqual(pieces.count, 1, "only the copy that finished logs a piece")
        XCTAssertEqual(pieces.first?.f["copy"], .int(2))
        XCTAssertNil(sink.events.first { $0.msg == "copy" })
    }

    func testHurryUsesSmallPieces() async throws {
        let cdn = SimCDN(size: 8_000_000)
        let transport = RecordingTransport(cdn)
        let downloader = RangeDownloader(ctx: context(transport))
        let resolver = TestEngine.resolver()
        for try await _ in downloader.stream(ByteRange(start: 0, end: 4 * 1_048_576 - 1)!, resolver: resolver, startup: false,
                                             priority: 50, deadline: nil) {}
        let asked = transport.requests.current.count
        let range = ByteRange(start: 4 * 1_048_576, end: 6 * 1_048_576 - 1)!
        var bytes: [UInt8] = []
        for try await chunk in downloader.stream(range, resolver: resolver, startup: false, priority: 50, deadline: nil, hurry: { true }) {
            bytes += chunk
        }
        XCTAssertEqual(bytes, Array(cdn.content[Int(range.start)...Int(range.end)]))
        // 2 MiB over the 7 connections left beside the rescue slot, not the warm meter's larger pieces.
        let pieces = transport.requests.current.dropFirst(asked).map(\.range)
        XCTAssertGreaterThanOrEqual(Set(pieces.map(\.start)).count, 7, "\(pieces)")
        for piece in pieces { XCTAssertLessThanOrEqual(piece.length, 300 * 1024, "\(piece)") }
    }

    func testWarmNodesSkipTheProbeHead() async throws {
        let cdn = SimCDN(size: 4_000_000)
        let transport = RecordingTransport(cdn)
        let downloader = RangeDownloader(ctx: context(transport))
        let resolver = TestEngine.resolver()
        func read(_ range: ByteRange) async throws -> [(node: String, range: ByteRange)] {
            let asked = transport.requests.current.count
            var bytes: [UInt8] = []
            for try await chunk in downloader.stream(range, resolver: resolver, startup: true, priority: 50, deadline: nil, hurry: { true }) {
                bytes += chunk
            }
            XCTAssertEqual(bytes, Array(cdn.content[Int(range.start)...Int(range.end)]))
            return Array(transport.requests.current.dropFirst(asked))
        }
        func head(of range: ByteRange) -> ByteRange { ByteRange(start: range.start, end: range.start + 65_535)! }

        // Review focus 3: with no node known the head is still raced over every node.
        let first = mebibyte
        let cold = try await read(first)
        XCTAssertGreaterThan(cold.filter { $0.range == head(of: first) }.count, 1, "\(cold.map(\.range))")

        let second = ByteRange(start: 2_000_000, end: 3_048_575)!
        let warm = try await read(second)
        XCTAssertFalse(warm.contains { $0.range == head(of: second) }, "\(warm.map(\.range))")
        XCTAssertEqual(warm.filter { $0.range.start == second.start }.count, 1, "one ordinary piece starts the range")
    }

    func testHurryHedgeBudgets() {
        let clock = ManualClock()
        let pieces = PieceDownloader(ctx: EngineContext(transport: SimCDN(size: 1), pool: ConnectionPool(limit: 1), config: TestEngine.config,
                                                        meter: Meter(), stats: EngineStats(), auto: nil, clock: clock.clock,
                                                        logger: Logger(session: "test")))
        let length: Int64 = 1_000_000
        func copy(received: Int = 0, headers: Bool = false) -> AttemptProgress {
            let progress = AttemptProgress()
            progress.begin(at: 0, length: length, base: Prefix())
            if headers { progress.headers(at: 0) }
            if received > 0 { progress.append([UInt8](repeating: 0, count: received), at: 0) }
            return progress
        }
        func due(_ progress: AttemptProgress, _ url: String, at ms: Double) -> Bool {
            clock.set(ms)
            return pieces.hurryHedgeDue(previous: progress, url: url, pieceLength: length)
        }

        // No first byte yet: twice the node's usual first byte, kept within 250-600 ms; 250 ms when unknown.
        let unknown = url(on: TestEngine.cosov)
        XCTAssertFalse(due(copy(), unknown, at: 200))
        XCTAssertTrue(due(copy(), unknown, at: 260))
        let ttfb = [100.0: url(on: TestEngine.aliov), 200: url(on: TestEngine.hk1), 400: url(on: TestEngine.hk3)]
        for (ms, url) in ttfb { pieces.ctx.nodes.firstByte(url, ms: ms) }
        XCTAssertFalse(due(copy(), ttfb[100]!, at: 240))
        XCTAssertTrue(due(copy(), ttfb[100]!, at: 260), "budget 250")
        XCTAssertFalse(due(copy(), ttfb[200]!, at: 390))
        XCTAssertTrue(due(copy(), ttfb[200]!, at: 410), "budget 400")
        XCTAssertFalse(due(copy(), ttfb[400]!, at: 590))
        XCTAssertTrue(due(copy(), ttfb[400]!, at: 610), "budget 600, the cap")

        // Bytes stopped arriving: 1 s since the last one, though 80% is in.
        let stopped = copy(received: 800_000, headers: true)
        XCTAssertFalse(due(stopped, unknown, at: 990))
        XCTAssertTrue(due(stopped, unknown, at: 1_000))

        // Slow: 100 ms first byte and 5 MB/s make 300 ms expected for the piece, so a copy is due from 600 ms
        // while under 75% has arrived.
        let measured = url(on: "cn-hk-eq-01-02.bilivideo.com")
        let nodes = pieces.ctx.nodes
        nodes.begin(measured); nodes.firstByte(measured, ms: 100); nodes.body(measured, bytes: 1_000_000, ms: 200); nodes.end(measured, receiving: true)
        XCTAssertEqual(nodes.expectedMs(measured, pieceBytes: length)!, 300, accuracy: 0.5)
        func slow(received: Int, at ms: Double) -> Bool {
            let progress = copy(received: received, headers: true)
            progress.append([], at: ms - 100)
            return due(progress, measured, at: ms)
        }
        XCTAssertFalse(slow(received: 500_000, at: 550))
        XCTAssertTrue(slow(received: 700_000, at: 610))
        XCTAssertFalse(slow(received: 800_000, at: 610), "most of the piece is in")
    }

    /// Two fast nodes both slow over a part of the file they have not served lately, a third one normal.
    let akamai = "upos-hz-mirrorakam.akamaized.net"
    let coldSpan = Int64(2_000_000)...Int64(4_000_000)
    let hurryRange = ByteRange(start: 2_000_000, end: 3_048_575)!

    /// The first byte of a cold request takes 1.5 s and the transfer pauses between chunks; the timeouts leave
    /// that to the copies.
    var coldConfig: RipperConfig {
        var config = TestEngine.slowConfig
        config.firstByteTimeoutMs = 5_500
        config.attemptTimeoutMs = 15_000
        // Room for three copies of every 64 KiB piece of a 1 MiB range.
        config.fixedConcurrency = 64
        return config
    }

    func coldRangeRun(hurry: (@Sendable () -> Bool)?, config: RipperConfig? = nil) async throws
        -> (seconds: Double, requests: [(node: String, range: ByteRange)]) {
        let cdn = SimCDN(size: 6_000_000, behaviors: [
            TestEngine.cosov: .init(coldRange: coldSpan, coldRangeFirstByteMs: 1_500, coldRangeBytesPerSecond: 100_000),
            akamai: .init(coldRange: coldSpan, coldRangeFirstByteMs: 1_500, coldRangeBytesPerSecond: 100_000),
            TestEngine.aliov: .init(bytesPerSecond: 4_000_000),
        ])
        let transport = RecordingTransport(cdn)
        let cosovURL = url(on: TestEngine.cosov)
        let resolver = Resolver(primary: cosovURL, backups: [],
                                mode: .custom([NodeAddress(host: TestEngine.cosov), NodeAddress(host: akamai), NodeAddress(host: TestEngine.aliov)]),
                                bans: BanList())
        XCTAssertEqual(resolver.urls().map(NodeCatalog.nodeKey(of:)), [TestEngine.cosov, akamai, TestEngine.aliov])
        let downloader = RangeDownloader(ctx: context(transport, config: config ?? coldConfig))
        for try await _ in downloader.stream(mebibyte, resolver: resolver, startup: false, priority: 50, deadline: nil) {}
        XCTAssertGreaterThan(resolver.speed(url(on: TestEngine.cosov)), resolver.speed(url(on: TestEngine.aliov)))
        let asked = transport.requests.current.count
        let started = Date()
        var bytes: [UInt8] = []
        for try await chunk in downloader.stream(hurryRange, resolver: resolver, startup: false, priority: 50, deadline: nil, hurry: hurry) {
            bytes += chunk
        }
        let seconds = Date().timeIntervalSince(started)
        XCTAssertEqual(bytes, Array(cdn.content[Int(hurryRange.start)...Int(hurryRange.end)]))
        return (seconds, Array(transport.requests.current.dropFirst(asked)))
    }

    /// Requests per piece, by the piece's end: a backup copy resumes partway, but ends where the piece ends.
    func copiesByPiece(_ requests: [(node: String, range: ByteRange)]) -> [Int64: [String]] {
        requests.reduce(into: [:]) { $0[$1.range.end, default: []].append($1.node) }
    }

    func testColdRangeOnTheTwoFastestNodesIsFetchedFromAThirdInAHurry() async throws {
        let (seconds, requests) = try await coldRangeRun(hurry: { true })
        XCTAssertLessThan(seconds, 1.4, "the old path needs at least 1.5 s")
        let pieces = copiesByPiece(requests)
        let rescued = pieces.values.filter { [TestEngine.cosov, akamai].contains($0.first) && $0.contains(TestEngine.aliov) }
        XCTAssertFalse(rescued.isEmpty, "\(pieces)")
        XCTAssertTrue(pieces.values.contains { $0.count == 3 }, "a third copy reached aliov: \(pieces)")
        XCTAssertTrue(pieces.values.allSatisfy { $0.count <= 3 }, "\(pieces)")
    }

    /// Review focus 4: outside a hurry a piece never gets a third copy.
    func testWithoutHurryNoThirdCopyStarts() async throws {
        let (_, requests) = try await coldRangeRun(hurry: nil)
        let pieces = copiesByPiece(requests)
        XCTAssertTrue(pieces.values.allSatisfy { $0.count <= 2 }, "\(pieces)")
    }

    func testHurryOffInConfigKeepsTheOldTiming() async throws {
        var config = coldConfig
        config.hurry = false
        let (seconds, requests) = try await coldRangeRun(hurry: { true }, config: config)
        XCTAssertGreaterThanOrEqual(seconds, 1.5)
        XCTAssertTrue(copiesByPiece(requests).values.allSatisfy { $0.count <= 2 }, "\(requests.map { "\($0.node) \($0.range)" })")
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
        XCTAssertLessThan(Date().timeIntervalSince(started), 6, "cosov's own piece takes about 1 s; the bound only catches an endless loop")
        XCTAssertTrue(sawFull.current, "cosov is capped at the one piece it was sending")
    }
}
