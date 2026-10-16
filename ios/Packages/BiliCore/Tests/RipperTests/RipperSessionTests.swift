import XCTest
import BiliShared
import DevLog
@testable import Ripper

/// Wraps a SimCDN: holds every request until opened, and refuses ranges from a given offset on with 403.
final class ScriptedTransport: RangeTransport, @unchecked Sendable {
    let cdn: SimCDN
    let open: Locked<Bool>
    let refuseFrom: Locked<Int64?>

    init(_ cdn: SimCDN, open: Bool = true, refuseFrom: Int64? = nil) {
        self.cdn = cdn
        self.open = Locked(open)
        self.refuseFrom = Locked(refuseFrom)
    }

    func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
        while !open.current { try await sleepMs(5) }
        if let from = refuseFrom.current, range.start >= from {
            try await sleepMs(2)
            return TransportResponse(status: 403, headers: [:], body: AsyncThrowingStream { $0.finish() })
        }
        return try await cdn.fetch(url, range: range)
    }
}

final class RipperSessionTests: XCTestCase {
    let size = 4 * 1024 * 1024
    let headerEnd: Int64 = 1_023
    let segmentLength: Int64 = 262_144

    func segments() -> [MediaSegment] {
        (0..<12).map { index in
            let start = headerEnd + 1 + Int64(index) * 262_144
            return MediaSegment(index: index, range: ByteRange(start: start, end: start + 262_143)!, startTime: Double(index) * 2, duration: 2)
        }
    }

    func makeSession(_ cdn: SimCDN) -> RipperSession {
        RipperSession(sources: [.video: (TestEngine.primary, [])], mode: .overseas, config: TestEngine.config,
                      transport: cdn, auto: nil, logger: Logger(session: "test"))
    }

    /// One retry round, so a refused range fails at once.
    var quickConfig: RipperConfig {
        var config = TestEngine.config
        config.pieceRounds = 1
        return config
    }

    func makeSession(_ transport: RangeTransport, config: RipperConfig, tracks: [TrackKind] = [.video],
                     auto: AutoConcurrency? = nil) -> RipperSession {
        var sources: [TrackKind: (primary: String, backups: [String])] = [:]
        for track in tracks { sources[track] = (TestEngine.primary, []) }
        return RipperSession(sources: sources, mode: .overseas, config: config, transport: transport, auto: auto,
                             logger: Logger(session: "test"))
    }

    func read(_ session: RipperSession, _ range: ByteRange, _ track: TrackKind = .video) async throws -> [UInt8] {
        var bytes: [UInt8] = []
        for try await chunk in session.read(track, range) { bytes += chunk }
        return bytes
    }

    func readError(_ session: RipperSession, _ range: ByteRange, _ track: TrackKind = .video) async -> Error? {
        do {
            _ = try await read(session, range, track)
            return nil
        } catch {
            return error
        }
    }

    func waitUntil(timeout: Double = 10, file: StaticString = #filePath, line: UInt = #line,
                   _ condition: () -> Bool) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("timed out waiting", file: file, line: line)
                return
            }
            try await sleepMs(10)
        }
    }

    func testHeadersSegmentsAndPrefetch() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        let headers = try await session.loadHeaders(.video, through: headerEnd)
        XCTAssertEqual(headers.bytes, Array(cdn.content[0...1_023]))
        XCTAssertEqual(headers.totalSize, Int64(size))
        session.setSegments(.video, segments())
        let first = segments()[0].range
        let firstBytes = try await read(session, first)
        XCTAssertEqual(firstBytes, Array(cdn.content[Int(first.start)...Int(first.end)]))
        try await Task.sleep(nanoseconds: 500_000_000)
        let second = segments()[1].range
        let secondBytes = try await read(session, second)
        XCTAssertEqual(secondBytes, Array(cdn.content[Int(second.start)...Int(second.end)]))
        XCTAssertGreaterThanOrEqual(session.stats().cacheHits, 1)
        session.close()
    }

    func testHeaderBytesAreServedFromMemory() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        _ = try await session.loadHeaders(.video, through: headerEnd)
        let before = cdn.requestCount()
        let bytes = try await read(session, ByteRange(start: 0, end: 99)!)
        XCTAssertEqual(bytes, Array(cdn.content[0...99]))
        XCTAssertEqual(cdn.requestCount(), before)
    }

    func testSeekAndUnalignedRanges() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        session.setSegments(.video, segments())
        let late = segments()[9].range
        let lateBytes = try await read(session, late)
        XCTAssertEqual(lateBytes, Array(cdn.content[Int(late.start)...Int(late.end)]))
        let odd = ByteRange(start: 5_000, end: 70_000)!
        let oddBytes = try await read(session, odd)
        XCTAssertEqual(oddBytes, Array(cdn.content[5_000...70_000]))
    }

    func testFatalWhenEveryNodeRefuses() async {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(status: 403) }
        let session = makeSession(SimCDN(size: size, behaviors: behaviors))
        let fatal = Locked(false)
        session.onFatal = { _ in fatal.withLock { $0 = true } }
        do {
            _ = try await read(session, ByteRange(start: 2_000, end: 50_000)!)
            XCTFail("expected a failure")
        } catch {}
        XCTAssertTrue(fatal.current)
    }

    func testReadsAreCheckedAgainstTheTotalFromTheHeaders() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        _ = try await session.loadHeaders(.video, through: headerEnd)
        session.setSegments(.video, segments())
        for node in NodeCatalog.overseas { cdn.set(node, .init(totalSize: Int64(size) + 1)) }
        let error = await readError(session, segments()[0].range)
        XCTAssertEqual(error as? RipperError, .totalMismatch, "nodes agreeing with each other on a wrong size are still wrong")
        session.close()
    }

    func testClosedSessionRefusesReads() async {
        let session = makeSession(SimCDN(size: size))
        session.close()
        do {
            _ = try await read(session, ByteRange(start: 2_000, end: 3_000)!)
            XCTFail("expected closed")
        } catch {
            XCTAssertEqual(error as? RipperError, .closed)
        }
    }

    func testReplacedURLsKeepWorking() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        session.replaceURLs(.video, primary: TestEngine.primary.replacingOccurrences(of: "deadline=9", with: "deadline=99"), backups: [])
        let range = ByteRange(start: 2_000, end: 80_000)!
        let bytes = try await read(session, range)
        XCTAssertEqual(bytes, Array(cdn.content[2_000...80_000]))
    }

    func testPrefetchStaysUnderEachTracksCap() async throws {
        var config = TestEngine.config
        config.prefetchVideoBytes = 3 * segmentLength
        config.prefetchAudioBytes = segmentLength
        let session = makeSession(SimCDN(size: size), config: config, tracks: [.video, .audio])
        session.setSegments(.video, segments())
        session.setSegments(.audio, segments())
        func settled() -> Bool {
            XCTAssertLessThanOrEqual(session.prefetchedBytes(.video), config.prefetchVideoBytes)
            XCTAssertLessThanOrEqual(session.prefetchedBytes(.audio), config.prefetchAudioBytes)
            return session.prefetchesRunning(.video) == 0 && session.prefetchesRunning(.audio) == 0
        }
        _ = try await read(session, segments()[0].range, .video)
        _ = try await read(session, segments()[0].range, .audio)
        try await waitUntil(settled)
        XCTAssertEqual(session.cachedBytes(.video), 3 * segmentLength)
        XCTAssertEqual(session.cachedBytes(.audio), segmentLength)

        let hitsBefore = session.stats().cacheHits
        _ = try await read(session, segments()[1].range, .video)
        XCTAssertEqual(session.stats().cacheHits, hitsBefore + 1)
        try await waitUntil(settled)
        XCTAssertEqual(session.cachedBytes(.video), 3 * segmentLength)

        session.dropCache()
        XCTAssertEqual(session.prefetchedBytes(.video), 0)
        XCTAssertEqual(session.prefetchedBytes(.audio), 0)

        _ = try await read(session, segments()[6].range, .video)
        try await waitUntil(settled)
        XCTAssertEqual(session.cachedBytes(.video), 3 * segmentLength)
        session.close()
        XCTAssertEqual(session.prefetchedBytes(.video), 0)
        XCTAssertEqual(session.prefetchedBytes(.audio), 0)
    }

    func testSeekReplacesTheTracksPrefetchedSegments() async throws {
        var config = TestEngine.config
        config.prefetchVideoBytes = 3 * segmentLength
        let session = makeSession(SimCDN(size: size), config: config)
        session.setSegments(.video, segments())
        _ = try await read(session, segments()[6].range)
        try await waitUntil { session.prefetchesRunning(.video) == 0 }
        XCTAssertEqual(session.cachedBytes(.video), 3 * segmentLength)
        _ = try await read(session, segments()[0].range)
        try await waitUntil { session.prefetchesRunning(.video) == 0 }
        XCTAssertEqual(session.cachedBytes(.video), 3 * segmentLength)
        let hitsBefore = session.stats().cacheHits
        _ = try await read(session, segments()[1].range)
        XCTAssertEqual(session.stats().cacheHits, hitsBefore + 1, "the new position is prefetched, not the one left behind")
        session.close()
    }

    func testPrefetchStopsAtTheLookAheadLimit() async throws {
        var config = TestEngine.config
        config.prefetchAheadSeconds = 5
        let session = makeSession(SimCDN(size: size), config: config)
        session.setSegments(.video, segments())
        _ = try await read(session, segments()[0].range)
        try await waitUntil { session.prefetchesRunning(.video) == 0 }
        // Segments start every 2 s: those at 2 s and 4 s are within 5 s of the playhead at 0.
        XCTAssertEqual(session.cachedBytes(.video), 2 * segmentLength)
        session.updatePlayhead(seconds: 9, rate: 1)
        XCTAssertEqual(session.cachedBytes(.video), 0, "segments that ended over 2 s behind the playhead are dropped")
        session.close()
    }

    func testPipelinedAndReorderedRequestsAreNotSeeks() async throws {
        var config = TestEngine.config
        config.prefetchVideoBytes = 0
        let transport = ScriptedTransport(SimCDN(size: size))
        let session = makeSession(transport, config: config)
        session.setSegments(.video, segments())
        let all = segments()
        _ = try await read(session, all[0].range)
        XCTAssertEqual(session.seekCount, 1, "the first request of a track starts up like a seek")

        func overlapping(_ first: Int, _ second: Int) async throws {
            transport.open.withLock { $0 = false }
            let before = session.mediaRequestCount
            async let a = read(session, all[first].range)
            try await waitUntil { session.mediaRequestCount == before + 1 }
            async let b = read(session, all[second].range)
            try await waitUntil { session.mediaRequestCount == before + 2 }
            transport.open.withLock { $0 = true }
            let (bytesA, bytesB) = try await (a, b)
            XCTAssertEqual(Int64(bytesA.count), segmentLength)
            XCTAssertEqual(Int64(bytesB.count), segmentLength)
        }
        try await overlapping(1, 2)
        XCTAssertEqual(session.seekCount, 1, "segment 2 asked for while 1 is still loading")
        try await overlapping(4, 3)
        XCTAssertEqual(session.seekCount, 1, "two neighbouring requests arriving out of order")

        _ = try await read(session, all[9].range)
        XCTAssertEqual(session.seekCount, 2)
        _ = try await read(session, all[0].range)
        XCTAssertEqual(session.seekCount, 3)
        _ = try await read(session, ByteRange(start: 5_000, end: 70_000)!)
        XCTAssertEqual(session.seekCount, 3, "inside the previous request")
        session.close()
    }

    func testPrefetchFailuresAreOnlyLoggedAndAPlayerFailureSignalsOnce() async throws {
        let all = segments()
        let transport = ScriptedTransport(SimCDN(size: size), refuseFrom: all[1].range.start)
        let session = makeSession(transport, config: quickConfig)
        session.setSegments(.video, all)
        let fatal = Locked(0)
        session.onFatal = { _ in fatal.withLock { $0 += 1 } }
        _ = try await read(session, all[0].range)
        try await waitUntil { session.prefetchesRunning(.video) == 0 }
        XCTAssertEqual(fatal.current, 0)
        XCTAssertEqual(session.cachedBytes(.video), 0)
        do {
            _ = try await read(session, all[1].range)
            XCTFail("expected a failure")
        } catch {
            XCTAssertNotEqual(error as? RipperError, .closed)
        }
        XCTAssertEqual(fatal.current, 1)
        session.close()
    }

    func testRequestsFailingTogetherSignalOnce() async throws {
        let transport = ScriptedTransport(SimCDN(size: size), open: false, refuseFrom: 0)
        let session = makeSession(transport, config: quickConfig, tracks: [.video, .audio])
        session.setSegments(.video, segments())
        session.setSegments(.audio, segments())
        let fatal = Locked(0)
        session.onFatal = { _ in fatal.withLock { $0 += 1 } }
        async let video = readError(session, segments()[0].range, .video)
        async let audio = readError(session, segments()[0].range, .audio)
        try await waitUntil { session.mediaRequestCount == 2 }
        transport.open.withLock { $0 = true }
        let errors = await [video, audio]
        XCTAssertNotNil(errors[0])
        XCTAssertNotNil(errors[1])
        XCTAssertEqual(fatal.current, 1)
        // A request made after the signal (say, after the URLs were refreshed) can signal again.
        let later = await readError(session, segments()[1].range, .video)
        XCTAssertNotNil(later)
        XCTAssertEqual(fatal.current, 2)
        session.close()
    }

    func testCloseEndsRunningReadsWithoutSignalling() async throws {
        let transport = ScriptedTransport(SimCDN(size: size), open: false)
        let session = makeSession(transport, config: TestEngine.config)
        session.setSegments(.video, segments())
        let fatal = Locked(false)
        session.onFatal = { _ in fatal.withLock { $0 = true } }
        async let pending = readError(session, segments()[0].range)
        try await waitUntil { session.mediaRequestCount == 1 }
        session.close()
        let error = await pending
        XCTAssertEqual(error as? RipperError, .closed)
        XCTAssertFalse(fatal.current)
        do {
            _ = try await session.loadHeaders(.video, through: headerEnd)
            XCTFail("expected closed")
        } catch {
            XCTAssertEqual(error as? RipperError, .closed)
        }
    }

    func testAutoConcurrencyHandlerFollowsTheOpenSessionOnly() {
        var config = TestEngine.config
        config.fixedConcurrency = nil

        let alone = AutoConcurrency()
        let closed = makeSession(SimCDN(size: 1_024), config: config, auto: alone)
        let limit = closed.stats().concurrency
        closed.close()
        alone.pushback(status: 429)
        XCTAssertNotEqual(alone.threads, limit)
        XCTAssertEqual(closed.stats().concurrency, limit, "a closed session ignores the shared connection count")

        let shared = AutoConcurrency()
        let old = makeSession(SimCDN(size: 1_024), config: config, auto: shared)
        let new = makeSession(SimCDN(size: 1_024), config: config, auto: shared)
        XCTAssertEqual(new.stats().concurrency, shared.threads)
        old.close()
        shared.pushback(status: 429)
        XCTAssertEqual(new.stats().concurrency, shared.threads, "closing the old session must not unhook the new one")
        new.close()
    }
}
