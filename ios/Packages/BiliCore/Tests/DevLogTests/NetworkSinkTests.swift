import XCTest
import BiliShared
@testable import DevLog

private struct Offline: Error {}

final class NetworkSinkTests: XCTestCase {
    private func event(_ seq: Int64) -> LogEvent {
        LogEvent(t: 0, seq: seq, session: "s", level: .info, cat: .app, msg: "m\(seq)", f: [:])
    }

    func testRetriesUntilPosterSucceedsAndAcknowledges() async {
        let attempts = Locked(0)
        let bodies = Locked<[Data]>([])
        let sink = NetworkSink(poster: { data in
            let attempt = attempts.withLock { value -> Int in value += 1; return value }
            if attempt == 1 { throw Offline() }
            bodies.withLock { $0.append(data) }
        })
        let acked = Locked<[String: Int64]>([:])
        sink.onAcknowledged = { session, seq in acked.withLock { $0[session] = seq } }
        sink.enqueue([event(1), event(2)])

        let first = await sink.flushOnce()
        XCTAssertFalse(first)
        XCTAssertEqual(sink.pending, 2)
        guard case .failing = sink.state else { return XCTFail("expected failing state") }

        let second = await sink.flushOnce()
        XCTAssertTrue(second)
        XCTAssertEqual(sink.pending, 0)
        XCTAssertEqual(sink.state, .connected)
        let lines = String(decoding: bodies.current[0], as: UTF8.self).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(acked.current["s"], 2)
    }

    func testNonFiniteFieldIsDeliveredAndAcknowledged() async {
        let bodies = Locked<[Data]>([])
        let sink = NetworkSink(poster: { data in bodies.withLock { $0.append(data) } })
        let acked = Locked<[String: Int64]>([:])
        sink.onAcknowledged = { session, seq in acked.withLock { $0[session] = seq } }
        sink.enqueue([LogEvent(t: 0, seq: 7, session: "s", level: .info, cat: .engine, msg: "inf", f: ["v": .double(.infinity)])])
        let ok = await sink.flushOnce()
        XCTAssertTrue(ok)
        XCTAssertEqual(bodies.current.count, 1)
        XCTAssertTrue(String(decoding: bodies.current[0], as: UTF8.self).contains("\"inf\""))
        XCTAssertEqual(acked.current["s"], 7)
    }

    func testUnencodableEventIsNeverAcknowledged() async {
        struct Unencodable: Error {}
        let bodies = Locked<[Data]>([])
        let sink = NetworkSink(poster: { data in bodies.withLock { $0.append(data) } })
        sink.encodeOverride = { event in
            if event.seq == 2 { throw Unencodable() }
            return try JSONEncoder().encode(event)
        }
        let acked = Locked<[String: Int64]>([:])
        sink.onAcknowledged = { session, seq in acked.withLock { $0[session] = seq } }
        sink.enqueue([event(1), event(2), event(3)])
        let ok = await sink.flushOnce()
        XCTAssertTrue(ok)
        XCTAssertEqual(String(decoding: bodies.current[0], as: UTF8.self).split(separator: "\n").count, 2)
        XCTAssertEqual(sink.pending, 0)
        XCTAssertEqual(acked.current["s"], 1)
    }

    func testPrependGoesAheadOfLiveEventsAndTheCapDropsOldest() {
        let sink = NetworkSink(poster: { _ in }, maxBuffered: 4)
        sink.enqueue([event(10), event(11)])
        sink.prepend([event(1), event(2), event(3)])
        XCTAssertEqual(sink.pending, 4)
        XCTAssertEqual(sink.bufferedForTesting.map(\.seq), [2, 3, 10, 11])
    }

    func testRetryDelayDoublesToTheCapAndResetsOnSuccess() {
        var delay = 500.0
        var seen: [Double] = []
        for _ in 0..<8 {
            delay = NetworkSink.nextDelay(after: false, current: delay, interval: 500, cap: 30_000)
            seen.append(delay)
        }
        XCTAssertEqual(seen, [1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000, 30_000])
        XCTAssertEqual(NetworkSink.nextDelay(after: true, current: delay, interval: 500, cap: 30_000), 500)
    }

    func testBufferCapDropsOldest() async {
        let bodies = Locked<[Data]>([])
        let sink = NetworkSink(poster: { data in bodies.withLock { $0.append(data) } }, maxBuffered: 3)
        sink.enqueue((1...5).map(event))
        XCTAssertEqual(sink.pending, 3)
        await sink.flushOnce()
        let seqs = String(decoding: bodies.current[0], as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? JSONDecoder().decode(LogEvent.self, from: Data($0.utf8)).seq }
        XCTAssertEqual(seqs, [3, 4, 5])
    }
}
