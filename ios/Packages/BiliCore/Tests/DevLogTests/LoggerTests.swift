import XCTest
@testable import DevLog

final class LoggerTests: XCTestCase {
    func testDeliversToSinksWithIncreasingSeq() {
        let logger = Logger(session: "s1")
        let sink = MemorySink()
        logger.add(sink)
        logger.info(.engine, "piece", ["bytes": 65536, "node": "a"])
        logger.warn(.api, "Cookie: SESSDATA=x")
        XCTAssertEqual(sink.events.map(\.seq), [1, 2])
        XCTAssertEqual(sink.events[0].f["bytes"], .int(65536))
        XCTAssertEqual(sink.events[0].session, "s1")
        XCTAssertEqual(sink.events[1].level, .warn)
        XCTAssertEqual(sink.events[1].msg, "Cookie: SESSDATA=[redacted]")
        logger.remove(sink)
        logger.info(.app, "after removal")
        XCTAssertEqual(sink.events.count, 2)
    }

    func testEventRoundTrip() throws {
        let event = LogEvent(t: 1.5, seq: 1, session: "s", level: .info, cat: .app, msg: "m",
                             f: ["a": "x", "b": 3, "c": 1.5, "d": true])
        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(LogEvent.self, from: data), event)
    }
}
