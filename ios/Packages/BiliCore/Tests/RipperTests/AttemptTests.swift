import XCTest
import BiliShared
@testable import Ripper

final class AttemptTests: XCTestCase {
    func url(_ node: String) -> String { TestEngine.primary.replacingOccurrences(of: "upos-sz-mirrorcos.bilivideo.com", with: node) }

    func run(_ cdn: SimCDN, node: String, range: ByteRange, resolver: Resolver = TestEngine.resolver()) async throws -> AttemptOutput {
        let runner = AttemptRunner(ctx: TestEngine.context(cdn))
        return try await runner.run(url: url(node), piece: range, progress: AttemptProgress(), resolver: resolver,
                                    priority: 0, queueClass: .ordinary, deadline: nil, resumeBase: { Prefix() })
    }

    func run(_ ctx: EngineContext, node: String, range: ByteRange, resolver: Resolver,
             progress: AttemptProgress = AttemptProgress()) async throws -> AttemptOutput {
        try await AttemptRunner(ctx: ctx).run(url: url(node), piece: range, progress: progress, resolver: resolver,
                                              priority: 0, queueClass: .ordinary, deadline: nil, resumeBase: { Prefix() })
    }

    /// Slow simulated nodes pause between chunks; leave room for that on a loaded runner.
    func slowConfig() -> RipperConfig {
        var config = TestEngine.config
        config.stallTimeoutMs = 2_000
        return config
    }

    func testDeliversExactBytesAndMeasuresTheNode() async throws {
        let cdn = SimCDN(size: 300_000)
        let resolver = TestEngine.resolver()
        let range = ByteRange(start: 1_000, end: 200_999)!
        let output = try await run(cdn, node: TestEngine.cosov, range: range, resolver: resolver)
        XCTAssertEqual(output.bytes, Array(cdn.content[1_000...200_999]))
        XCTAssertEqual(output.total, 300_000)
        XCTAssertGreaterThan(resolver.speed(url(TestEngine.cosov)), 0)
    }

    func testRejectsWrongStatusAndRange() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(status: 200), TestEngine.aliov: .init(wrongRange: true)])
        for node in [TestEngine.cosov, TestEngine.aliov] {
            do {
                _ = try await run(cdn, node: node, range: ByteRange(start: 0, end: 9_999)!)
                XCTFail("expected a failure for \(node)")
            } catch {
                XCTAssertNotNil((error as? RipperError)?.status)
            }
        }
    }

    func testTruncatedBodyIsALengthMismatch() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(truncateAfter: 20_000)])
        do {
            _ = try await run(cdn, node: TestEngine.cosov, range: ByteRange(start: 0, end: 49_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .lengthMismatch(got: 20_000, expected: 50_000))
        }
    }

    func testTimeouts() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 1_000), TestEngine.aliov: .init(stallAfter: 16_384)])
        do {
            _ = try await run(cdn, node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!)
            XCTFail("expected first byte timeout")
        } catch {
            XCTAssertEqual(error as? RipperError, .firstByteTimeout)
        }
        do {
            _ = try await run(cdn, node: TestEngine.aliov, range: ByteRange(start: 0, end: 49_999)!)
            XCTFail("expected stall")
        } catch {
            XCTAssertEqual(error as? RipperError, .stalled)
        }
    }

    func testResumeBaseIsPrepended() async throws {
        let cdn = SimCDN(size: 100_000)
        let range = ByteRange(start: 0, end: 99_999)!
        let base = Prefix(bytes: 40_000, chunks: [Array(cdn.content[0..<40_000])])
        let runner = AttemptRunner(ctx: TestEngine.context(cdn))
        let output = try await runner.run(url: url(TestEngine.cosov), piece: range, progress: AttemptProgress(), resolver: TestEngine.resolver(),
                                          priority: 0, queueClass: .ordinary, deadline: nil, resumeBase: { base })
        XCTAssertEqual(output.bytes, cdn.content)
    }

    func testResumeAsksOnlyForTheMissingTail() async throws {
        let cdn = SimCDN(size: 100_000)
        let ctx = TestEngine.context(cdn)
        let base = Prefix(bytes: 40_000, chunks: [Array(cdn.content[0..<40_000])])
        let progress = AttemptProgress()
        let output = try await AttemptRunner(ctx: ctx).run(url: url(TestEngine.cosov), piece: ByteRange(start: 0, end: 99_999)!,
                                                           progress: progress, resolver: TestEngine.resolver(), priority: 0,
                                                           queueClass: .ordinary, deadline: nil, resumeBase: { base })
        XCTAssertEqual(output.bytes.count, 100_000)
        XCTAssertEqual(progress.received, 60_000)
    }

    func testAttemptTimeout() async {
        var config = slowConfig()
        config.attemptTimeoutMs = 400
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 50_000)])
        let ctx = TestEngine.context(cdn, config: config)
        do {
            _ = try await run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 99_999)!, resolver: TestEngine.resolver())
            XCTFail("expected attempt timeout")
        } catch {
            XCTAssertEqual(error as? RipperError, .attemptTimeout)
        }
        XCTAssertEqual(ctx.pool.active, 0)
    }

    func testShortTransfersAreNotSpeedSamples() async throws {
        let cdn = SimCDN(size: 300_000)
        let ctx = TestEngine.context(cdn)
        let resolver = TestEngine.resolver()
        let target = url(TestEngine.cosov)
        _ = try await run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: Meter.sampleMinBytes - 2)!, resolver: resolver)
        XCTAssertEqual(resolver.speed(target), 0)
        XCTAssertEqual(ctx.meter.connectionBps, 0)
        _ = try await run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: Meter.sampleMinBytes - 1)!, resolver: resolver)
        XCTAssertGreaterThan(resolver.speed(target), 0)
        XCTAssertGreaterThan(ctx.meter.connectionBps, 0)
        let stats = ctx.stats.snapshot()
        XCTAssertEqual(stats.requests, 2)
        XCTAssertEqual(stats.failures, 0)
        XCTAssertEqual(ctx.pool.active, 0)
    }

    func testRefusingNodeIsStruck() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(failForMs: 60_000)])
        let ctx = TestEngine.context(cdn)
        let resolver = TestEngine.resolver()
        let target = url(TestEngine.cosov)
        XCTAssertTrue(resolver.rescueCandidates().contains(target))
        do {
            _ = try await run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!, resolver: resolver)
            XCTFail("expected a connection error")
        } catch {
            XCTAssertTrue(error is SimCDN.ConnectionLost)
        }
        XCTAssertFalse(resolver.rescueCandidates().contains(target))
        let stats = ctx.stats.snapshot()
        XCTAssertEqual(stats.failures, 1)
        XCTAssertEqual(stats.nodes.first { $0.node == TestEngine.cosov }?.failures, 1)
        XCTAssertEqual(ctx.pool.active, 0)
    }

    func testBadResponseStrikesTheNode() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(wrongRange: true)])
        let resolver = TestEngine.resolver()
        do {
            _ = try await run(cdn, node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!, resolver: resolver)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .badResponse(status: 206))
        }
        XCTAssertFalse(resolver.rescueCandidates().contains(url(TestEngine.cosov)))
    }

    func testPushbackStepsTheConnectionCountDown() async {
        let auto = AutoConcurrency()
        auto.newSession()
        XCTAssertEqual(auto.threads, 16)
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(status: 429)])
        let ctx = TestEngine.context(cdn, auto: auto)
        do {
            _ = try await run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!, resolver: TestEngine.resolver())
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .badResponse(status: 429))
        }
        XCTAssertEqual(auto.threads, 12)
    }

    func testCancelledCopyIsSampledButNotStruck() async throws {
        let cdn = SimCDN(size: 300_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 200_000)])
        let ctx = TestEngine.context(cdn, config: slowConfig())
        let resolver = TestEngine.resolver()
        let progress = AttemptProgress()
        let target = url(TestEngine.cosov)
        let task = Task {
            try await AttemptRunner(ctx: ctx).run(url: target, piece: ByteRange(start: 0, end: 299_999)!, progress: progress, resolver: resolver,
                                                  priority: 0, queueClass: .ordinary, deadline: nil, resumeBase: { Prefix() })
        }
        let giveUp = ProcessInfo.processInfo.systemUptime + 5
        while progress.received < Meter.sampleMinBytes, ProcessInfo.processInfo.systemUptime < giveUp {
            try await sleepMs(5)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertGreaterThan(resolver.speed(target), 0)
        XCTAssertTrue(resolver.rescueCandidates().contains(target))
        let stats = ctx.stats.snapshot()
        XCTAssertEqual(stats.requests, 1)
        XCTAssertEqual(stats.failures, 0)
        XCTAssertGreaterThanOrEqual(stats.duplicateBytes, Meter.sampleMinBytes)
        XCTAssertEqual(ctx.pool.active, 0)
    }

    func testMeterSmoothsAndSizesPieces() {
        let meter = Meter()
        XCTAssertEqual(meter.adaptiveMinChunk(base: 65_536, rangeLength: 4 << 20, pieceLimit: 16, hostCount: 4), 65_536)
        XCTAssertEqual(meter.hedgeDelayMs(configured: 900), 900)
        meter.record(bytes: Meter.sampleMinBytes - 1, elapsedMs: 10)
        XCTAssertEqual(meter.connectionBps, 0)
        meter.record(bytes: 1_000_000, elapsedMs: 200)
        XCTAssertEqual(meter.connectionBps, 5_000_000, accuracy: 0.1)
        meter.record(bytes: 1_000_000, elapsedMs: 1_000)
        XCTAssertEqual(meter.connectionBps, 3_800_000, accuracy: 0.1)
        XCTAssertEqual(meter.pieceMs, 440, accuracy: 0.001)
        XCTAssertEqual(meter.adaptiveMinChunk(base: 65_536, rangeLength: 4 << 20, pieceLimit: 16, hostCount: 4), 1 << 20)
        XCTAssertEqual(meter.adaptiveMinChunk(base: 65_536, rangeLength: 1 << 20, pieceLimit: 16, hostCount: 6), 174_763)
        XCTAssertEqual(meter.hedgeDelayMs(configured: 900), 660)
        XCTAssertEqual(meter.hedgeDelayMs(configured: 500), 500)
    }

    func testDuplicateShare() {
        let stats = EngineStats()
        stats.delivered(300)
        stats.failed(node: TestEngine.cosov, wastedBytes: 100, cancelled: true)
        let snapshot = stats.snapshot()
        XCTAssertEqual(snapshot.duplicateShare, 0.25, accuracy: 1e-9)
        XCTAssertEqual(snapshot.failures, 0)
    }
}
