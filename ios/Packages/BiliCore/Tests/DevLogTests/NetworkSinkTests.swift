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
