import XCTest
import BiliShared
import DevLog
@testable import Ripper

final class AttemptTests: XCTestCase {
    static func url(_ node: String) -> String { TestEngine.primary.replacingOccurrences(of: "upos-sz-mirrorcos.bilivideo.com", with: node) }

    static func run(_ ctx: EngineContext, node: String, range: ByteRange, resolver: Resolver = TestEngine.resolver(),
                    progress: AttemptProgress = AttemptProgress(),
                    resumeBase: @escaping @Sendable () -> Prefix = { Prefix() }) async throws -> AttemptOutput {
        try await AttemptRunner(ctx: ctx).run(url: url(node), piece: range, progress: progress, resolver: resolver,
                                              priority: 0, queueClass: .ordinary, deadline: nil, resumeBase: resumeBase)
    }

    func testDeliversExactBytesAndMeasuresTheNode() async throws {
        let cdn = SimCDN(size: 300_000)
        let resolver = TestEngine.resolver()
        let range = ByteRange(start: 1_000, end: 200_999)!
        let output = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: range, resolver: resolver)
        XCTAssertEqual(output.bytes, Array(cdn.content[1_000...200_999]))
        XCTAssertEqual(output.total, 300_000)
        XCTAssertGreaterThan(resolver.speed(Self.url(TestEngine.cosov)), 0)
    }

    func testRejectsWrongStatusAndRange() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(status: 200), TestEngine.aliov: .init(wrongRange: true)])
        for node in [TestEngine.cosov, TestEngine.aliov] {
            do {
                _ = try await Self.run(TestEngine.context(cdn), node: node, range: ByteRange(start: 0, end: 9_999)!)
                XCTFail("expected a failure for \(node)")
            } catch {
                XCTAssertNotNil((error as? RipperError)?.status)
            }
        }
    }

    func testMissingContentRangeIsABadResponse() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(omitContentRange: true)])
        do {
            _ = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .badResponse(status: 206))
        }
    }

    func testTruncatedBodyIsALengthMismatch() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(truncateAfter: 20_000)])
        let ctx = TestEngine.context(cdn)
        let sink = MemorySink()
        ctx.logger.add(sink)
        do {
            _ = try await Self.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 49_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .lengthMismatch(got: 20_000, expected: 50_000))
        }
        let failed = sink.events.first { $0.msg == "attempt failed" }
        XCTAssertEqual(failed?.f["range"], .string("0-49999"))
        XCTAssertEqual(failed?.f["node"], .string(TestEngine.cosov))
        XCTAssertEqual(failed?.f["bytes"], .int(20_000))
    }

    func testOverlongBodyIsALengthMismatch() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(extraBytes: 5_000)])
        do {
            _ = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(start: 0, end: 49_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .lengthMismatch(got: 55_000, expected: 50_000))
        }
    }

    func testAdvertisedTotalIsPassedOn() async throws {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(totalSize: 500_000)])
        let output = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!)
        XCTAssertEqual(output.total, 500_000)
    }

    func testTimeouts() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 1_000), TestEngine.aliov: .init(stallAfter: 16_384)])
        do {
            _ = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!)
            XCTFail("expected first byte timeout")
        } catch {
            XCTAssertEqual(error as? RipperError, .firstByteTimeout)
        }
        do {
            _ = try await Self.run(TestEngine.context(cdn), node: TestEngine.aliov, range: ByteRange(start: 0, end: 49_999)!)
            XCTFail("expected stall")
        } catch {
            XCTAssertEqual(error as? RipperError, .stalled)
        }
    }

    func testAttemptTimeout() async {
        var config = TestEngine.slowConfig
        config.attemptTimeoutMs = 400
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 50_000)])
        let ctx = TestEngine.context(cdn, config: config)
        do {
            _ = try await Self.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 99_999)!)
            XCTFail("expected attempt timeout")
        } catch {
            XCTAssertEqual(error as? RipperError, .attemptTimeout)
        }
        XCTAssertEqual(ctx.pool.active, 0)
    }

    func testSilentNodeAfterHeadersCountsAsSlow() async {
        let manual = ManualClock(100_000)
        let auto = AutoConcurrency(clock: manual.clock)
        auto.demand(active: 8, limit: 8, queued: 1)
        manual.advance(5_000)
        XCTAssertEqual(auto.threads, 8)
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(stallAfter: 0)])
        do {
            _ = try await Self.run(TestEngine.context(cdn, auto: auto), node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!)
            XCTFail("expected stall")
        } catch {
            XCTAssertEqual(error as? RipperError, .stalled)
        }
        XCTAssertEqual(auto.threads, 12)
    }

    func testResumeBaseIsPrepended() async throws {
        let cdn = SimCDN(size: 100_000)
        let range = ByteRange(start: 0, end: 99_999)!
        let base = Prefix(bytes: 40_000, chunks: [Array(cdn.content[0..<40_000])])
        let output = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: range, resumeBase: { base })
        XCTAssertEqual(output.bytes, cdn.content)
    }

    func testResumeAsksOnlyForTheMissingTail() async throws {
        let cdn = SimCDN(size: 100_000)
        let base = Prefix(bytes: 40_000, chunks: [Array(cdn.content[0..<40_000])])
        let progress = AttemptProgress()
        let output = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(start: 0, end: 99_999)!,
                                        progress: progress, resumeBase: { base })
        XCTAssertEqual(output.bytes.count, 100_000)
        XCTAssertEqual(progress.received, 60_000)
    }

    func testShortTransfersAreNotSpeedSamples() async throws {
        let cdn = SimCDN(size: 300_000)
        let ctx = TestEngine.context(cdn)
        let resolver = TestEngine.resolver()
        let target = Self.url(TestEngine.cosov)
        _ = try await Self.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: Meter.sampleMinBytes - 2)!, resolver: resolver)
        XCTAssertEqual(resolver.speed(target), 0)
        XCTAssertEqual(ctx.meter.connectionBps, 0)
        _ = try await Self.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: Meter.sampleMinBytes - 1)!, resolver: resolver)
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
        let target = Self.url(TestEngine.cosov)
        XCTAssertTrue(resolver.rescueCandidates().contains(target))
        do {
            _ = try await Self.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!, resolver: resolver)
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
            _ = try await Self.run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!, resolver: resolver)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .badResponse(status: 206))
        }
        XCTAssertFalse(resolver.rescueCandidates().contains(Self.url(TestEngine.cosov)))
    }

    func testPushbackStepsTheConnectionCountDown() async {
        let auto = AutoConcurrency()
        auto.newSession()
        XCTAssertEqual(auto.threads, 16)
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(status: 429)])
        do {
            _ = try await Self.run(TestEngine.context(cdn, auto: auto), node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .badResponse(status: 429))
        }
        XCTAssertEqual(auto.threads, 12)
    }

    func testCancelledCopyIsSampledButNotStruck() async throws {
        let cdn = SimCDN(size: 300_000, behaviors: [TestEngine.cosov: .init(bytesPerSecond: 200_000)])
        let ctx = TestEngine.context(cdn, config: TestEngine.slowConfig)
        let sink = MemorySink()
        ctx.logger.add(sink)
        let resolver = TestEngine.resolver()
        let progress = AttemptProgress()
        let target = Self.url(TestEngine.cosov)
        let task = Task {
            try await Self.run(ctx, node: TestEngine.cosov, range: ByteRange(start: 0, end: 299_999)!, resolver: resolver, progress: progress)
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
        let cancelled = sink.events.first { $0.msg == "attempt cancelled" }
        XCTAssertEqual(cancelled?.f["range"], .string("0-299999"))
        XCTAssertEqual(cancelled?.f["node"], .string(TestEngine.cosov))
        XCTAssertNil(sink.events.first { $0.msg == "attempt failed" })
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
