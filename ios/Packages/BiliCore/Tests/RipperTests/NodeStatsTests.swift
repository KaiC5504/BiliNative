import XCTest
import BiliShared
import DevLog
@testable import Ripper

final class NodeStatsTests: XCTestCase {
    func testExpectedTimeSharesTheNodeBeyondItsMeasuredLoad() {
        let stats = NodeStats()
        let url = "https://upos-sz-mirrorcosov.bilivideo.com/v.m4s"
        XCTAssertNil(stats.expectedMs(url, pieceBytes: 1_000_000))
        stats.begin(url); stats.firstByte(url, ms: 100); stats.body(url, bytes: 1_000_000, ms: 500); stats.end(url, receiving: true)
        // 2 MB/s on one connection, ttfb 100 ms, load blended from 1 in flight; width = max(4, load) = 4.
        XCTAssertEqual(stats.expectedMs(url, pieceBytes: 1_000_000)!, 600, accuracy: 0.5)
        // Six more in flight: 2 MB/s × 4 / 7 per connection.
        XCTAssertEqual(stats.expectedMs(url, pieceBytes: 1_000_000, extraInflight: 6)!, 100 + 1_000_000 / (2_000_000 * 4.0 / 7) * 1000, accuracy: 0.5)
    }

    func testSmallBodiesSayNothingAboutSpeed() {
        let stats = NodeStats(); let url = "https://a.example/v"
        stats.body(url, bytes: 16 * 1024, ms: 10)
        XCTAssertFalse(stats.isKnown(url))
    }

    func testSilenceWhileReceivingCapsTheNodeOtherwiseRaisesItsFirstByteTime() {
        let stats = NodeStats(); let busy = "https://akam.example/v"; let idle = "https://cosov.example/v"
        stats.begin(busy); stats.firstByte(busy, ms: 50)           // one transfer receiving
        stats.begin(busy); stats.begin(busy)                        // two more waiting
        stats.silent(busy, waitedMs: 5_500)
        XCTAssertTrue(stats.isBusy(busy))
        XCTAssertTrue(stats.isFull(busy), "limit = what it was receiving (1), and 3 are in flight")
        XCTAssertEqual(stats.ttfbMs(busy), 50, accuracy: 0.01, "a queued request is not the node's first-byte time")
        stats.silent(idle, waitedMs: 2_000)
        XCTAssertEqual(stats.ttfbMs(idle), 2_000, accuracy: 0.01)
    }

    func testOutrunAndCrawlOnlyEverLowerTheEstimate() {
        let stats = NodeStats(); let url = "https://aliov.example/v"
        stats.begin(url); stats.firstByte(url, ms: 40); stats.body(url, bytes: 4_000_000, ms: 1_000); stats.end(url, receiving: true)
        stats.outrun(url, waitedMs: 30)        // shorter than the known ttfb: ignored
        XCTAssertEqual(stats.ttfbMs(url), 40, accuracy: 0.01)
        stats.outrun(url, waitedMs: 1_040)     // blended up
        XCTAssertEqual(stats.ttfbMs(url), 40 * 0.7 + 1_040 * 0.3, accuracy: 0.01)
        stats.crawl(url, bytes: 50_000, ms: 200)   // under 300 ms: ignored
        XCTAssertEqual(stats.bps(url), 4_000_000, accuracy: 1)
        stats.crawl(url, bytes: 100_000, ms: 1_000) // 100 KB/s trickle
        XCTAssertEqual(stats.bps(url), 4_000_000 * 0.7 + 100_000 * 0.3, accuracy: 1)
    }

    func testRecordsAreKeyedByNodeNotByAddress() {
        let stats = NodeStats()
        stats.begin("https://a.example/one.m4s?sign=1")
        XCTAssertEqual(stats.inflight("https://a.example/two.m4s?sign=2"), 1)
        XCTAssertEqual(stats.inflight("https://b.example/one.m4s?sign=1"), 0)
        stats.end("https://a.example/other.m4s", receiving: false)
        stats.end("https://a.example/other.m4s", receiving: true)
        XCTAssertEqual(stats.inflight("https://a.example/one.m4s"), 0, "an unmatched end never goes below zero")
    }

    func testResetForgetsMeasurementsButNotRunningTransfers() {
        let stats = NodeStats(); let url = "https://a.example/v"
        stats.begin(url); stats.firstByte(url, ms: 80); stats.body(url, bytes: 1_000_000, ms: 500)
        stats.begin(url); stats.silent(url, waitedMs: 1_000)
        stats.reset()
        XCTAssertFalse(stats.isKnown(url))
        XCTAssertEqual(stats.ttfbMs(url), 0)
        XCTAssertEqual(stats.inflight(url), 2)
        XCTAssertTrue(stats.isBusy(url))
        XCTAssertFalse(stats.isFull(url), "the limit learnt on the old path is dropped")
        stats.end(url, receiving: true); stats.end(url, receiving: false)
        XCTAssertEqual(stats.inflight(url), 0)
        XCTAssertFalse(stats.isBusy(url))
    }

    func testAkamaiIsFullAtTheTransportsConnectionsPerHostFromTheStart() {
        let stats = NodeStats(connectionsPerHost: 8)
        let akamai = "https://upos-hz-mirrorakam.akamaized.net/v.m4s"
        let mirror = "https://upos-sz-mirrorcosov.bilivideo.com/v.m4s"
        for _ in 0..<7 { stats.begin(akamai); stats.begin(mirror) }
        XCTAssertFalse(stats.isFull(akamai))
        XCTAssertTrue(stats.isFull(akamai, extraInflight: 1))
        stats.begin(akamai); stats.begin(mirror)
        XCTAssertTrue(stats.isFull(akamai), "a ninth request would wait inside URLSession")
        XCTAssertFalse(stats.isFull(mirror), "HTTP/2 sends them all at once over one connection")
        stats.reset()
        XCTAssertTrue(stats.isFull(akamai), "a network change does not lift the transport's limit")
        XCTAssertFalse(NodeStats().isFull(akamai), "no limit when the transport has none")
    }

    func testBeginTakesTheFirstNodeWithRoom() {
        let stats = NodeStats(connectionsPerHost: 1)
        let akamai = "https://upos-hz-mirrorakam.akamaized.net/v.m4s"
        let mirror = "https://upos-sz-mirrorcosov.bilivideo.com/v.m4s"
        XCTAssertEqual(stats.begin(firstOpenOf: [akamai, mirror]), akamai)
        XCTAssertEqual(stats.begin(firstOpenOf: [akamai, mirror]), mirror)
        XCTAssertEqual(stats.begin(firstOpenOf: [akamai]), akamai, "the first one when every node is full")
        XCTAssertEqual(stats.inflight(akamai), 2)
        XCTAssertEqual(stats.inflight(mirror), 1)
    }

    func testRunnerFeedsTheStats() async throws {
        let cdn = SimCDN(size: 400_000, behaviors: [TestEngine.aliov: .init(firstByteMs: 1_000)])
        let ctx = TestEngine.context(cdn)
        let fast = AttemptTests.url(TestEngine.cosov)
        let silent = AttemptTests.url(TestEngine.aliov)

        _ = try await AttemptTests.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 299_999)!)
        XCTAssertTrue(ctx.nodes.isKnown(fast))
        XCTAssertGreaterThan(ctx.nodes.ttfbMs(fast), 0)
        XCTAssertEqual(ctx.nodes.inflight(fast), 0)
        XCTAssertFalse(ctx.nodes.isBusy(fast))

        do {
            _ = try await AttemptTests.run(ctx, node: TestEngine.aliov, range: ByteRange(start: 0, end: 299_999)!)
            XCTFail("expected first byte timeout")
        } catch {
            XCTAssertEqual(error as? RipperError, .firstByteTimeout)
        }
        XCTAssertGreaterThanOrEqual(ctx.nodes.ttfbMs(silent), TestEngine.config.firstByteTimeoutMs)
        XCTAssertFalse(ctx.nodes.isKnown(silent))
        XCTAssertEqual(ctx.nodes.inflight(silent), 0)
        XCTAssertFalse(ctx.nodes.isBusy(silent))
    }

    func testOutrunCopyCancelledBeforeAnyByteRaisesTheFirstByteTime() async throws {
        var config = TestEngine.slowConfig
        config.firstByteTimeoutMs = 5_000
        let cdn = SimCDN(size: 300_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 2_000)])
        let ctx = TestEngine.context(cdn, config: config)
        let url = AttemptTests.url(TestEngine.cosov)
        ctx.nodes.begin(url); ctx.nodes.firstByte(url, ms: 10); ctx.nodes.end(url, receiving: true)
        let progress = AttemptProgress()
        let task = Task { try await AttemptTests.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 99_999)!, progress: progress) }
        let giveUp = ProcessInfo.processInfo.systemUptime + 5
        while ctx.nodes.inflight(url) == 0, ProcessInfo.processInfo.systemUptime < giveUp { try await sleepMs(5) }
        try await sleepMs(200)
        progress.markOutrun()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertGreaterThan(ctx.nodes.ttfbMs(url), 40, "10 ms blended with the 200 ms or more it had waited")
        XCTAssertEqual(ctx.nodes.inflight(url), 0)
    }

    func testOutrunCopyCancelledWhileCrawlingLowersTheSpeed() async throws {
        let cdn = SimCDN(size: 300_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 100_000)])
        let ctx = TestEngine.context(cdn, config: TestEngine.slowConfig)
        let url = AttemptTests.url(TestEngine.cosov)
        ctx.nodes.begin(url); ctx.nodes.firstByte(url, ms: 5); ctx.nodes.body(url, bytes: 4_000_000, ms: 1_000); ctx.nodes.end(url, receiving: true)
        let progress = AttemptProgress()
        let task = Task { try await AttemptTests.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 299_999)!, progress: progress) }
        let giveUp = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < giveUp {
            let timing = progress.timing
            if timing.gotHeaders, progress.received > 0, ctx.clock.nowMs() - progress.headersAt >= 400 { break }
            try await sleepMs(5)
        }
        XCTAssertEqual(ctx.nodes.inflight(url), 1)
        XCTAssertTrue(ctx.nodes.isBusy(url))
        progress.markOutrun()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(ctx.nodes.bps(url), 4_000_000)
        XCTAssertGreaterThan(ctx.nodes.bps(url), 0)
        XCTAssertEqual(ctx.nodes.inflight(url), 0)
        XCTAssertFalse(ctx.nodes.isBusy(url))
    }

    /// A seek, a closed session or a cancelled player read ends a copy without any other copy having won.
    func testCopyCancelledForAnyOtherReasonLeavesTheNodeEstimatesAlone() async throws {
        var config = TestEngine.slowConfig
        config.firstByteTimeoutMs = 5_000
        let cdn = SimCDN(size: 300_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 2_000), TestEngine.aliov: .init(bytesPerSecond: 100_000)])
        let ctx = TestEngine.context(cdn, config: config)
        let waiting = AttemptTests.url(TestEngine.cosov)
        let crawling = AttemptTests.url(TestEngine.aliov)
        ctx.nodes.begin(waiting); ctx.nodes.firstByte(waiting, ms: 10); ctx.nodes.end(waiting, receiving: true)
        ctx.nodes.begin(crawling); ctx.nodes.firstByte(crawling, ms: 5)
        ctx.nodes.body(crawling, bytes: 4_000_000, ms: 1_000); ctx.nodes.end(crawling, receiving: true)

        let waitingProgress = AttemptProgress()
        let waitingTask = Task {
            try await AttemptTests.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 99_999)!, progress: waitingProgress)
        }
        let crawlingProgress = AttemptProgress()
        let crawlingTask = Task {
            try await AttemptTests.run(ctx, node: TestEngine.aliov, range: ByteRange(start: 0, end: 299_999)!, progress: crawlingProgress)
        }
        let giveUp = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < giveUp {
            if crawlingProgress.timing.gotHeaders, crawlingProgress.received > 0, ctx.clock.nowMs() - crawlingProgress.headersAt >= 400,
               waitingProgress.isStarted { break }
            try await sleepMs(5)
        }
        try await sleepMs(200)
        waitingTask.cancel()
        crawlingTask.cancel()
        for task in [waitingTask, crawlingTask] {
            do {
                _ = try await task.value
                XCTFail("expected cancellation")
            } catch {
                XCTAssertTrue(error is CancellationError, "\(error)")
            }
        }
        XCTAssertEqual(ctx.nodes.ttfbMs(waiting), 10, accuracy: 0.01)
        XCTAssertEqual(ctx.nodes.bps(crawling), 4_000_000, accuracy: 1)
        XCTAssertEqual(ctx.nodes.inflight(waiting), 0)
        XCTAssertEqual(ctx.nodes.inflight(crawling), 0)
    }

    func testNetworkChangeForgetsNodeStats() async throws {
        let session = RipperSession(sources: [.video: (TestEngine.primary, [])], mode: .overseas, config: TestEngine.config,
                                    transport: SimCDN(size: 1_000_000), auto: nil, logger: Logger(session: "test"))
        for try await _ in session.read(.video, ByteRange(start: 2_000, end: 400_000)!) {}
        let urls = NodeCatalog.representationURLs(primary: TestEngine.primary, backups: [], mode: .overseas, policy: .bilibili)
        XCTAssertTrue(urls.contains { session.nodeStats.isKnown($0) }, "the read measured at least one node")

        session.networkChanged(interfaceChanged: false)
        XCTAssertFalse(urls.contains { session.nodeStats.isKnown($0) })
    }
}
