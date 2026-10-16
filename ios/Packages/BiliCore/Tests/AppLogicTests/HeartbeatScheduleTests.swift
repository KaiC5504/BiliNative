import XCTest
@testable import AppLogic

final class HeartbeatScheduleTests: XCTestCase {
    func testHeartbeatEvery15SecondsOfPlaybackAndOnMarks() {
        var s = HeartbeatSchedule()
        XCTAssertNil(s.tick(position: 14, playing: true))
        XCTAssertEqual(s.tick(position: 15, playing: true), 15)
        XCTAssertNil(s.tick(position: 40, playing: false))
        XCTAssertEqual(s.mark(position: 40), 40)
        XCTAssertNil(s.tick(position: 54, playing: true))
        XCTAssertEqual(s.tick(position: 55, playing: true), 55)
    }

    func testPausedPlayerNeverBeats() {
        var s = HeartbeatSchedule()
        XCTAssertNil(s.tick(position: 100, playing: false))
        XCTAssertEqual(s.tick(position: 100, playing: true), 100)
    }

    func testCustomIntervalAndFractionalPositions() {
        var s = HeartbeatSchedule(interval: 5)
        XCTAssertNil(s.tick(position: 4.9, playing: true))
        XCTAssertEqual(s.tick(position: 5.4, playing: true), 5)
        XCTAssertNil(s.tick(position: 10.3, playing: true))
        XCTAssertEqual(s.tick(position: 10.4, playing: true), 10)
    }

    func testSeekingBackWaitsAFullIntervalFromTheMark() {
        var s = HeartbeatSchedule()
        XCTAssertEqual(s.tick(position: 60, playing: true), 60)
        XCTAssertEqual(s.mark(position: 10), 10)
        XCTAssertNil(s.tick(position: 24, playing: true))
        XCTAssertEqual(s.tick(position: 25, playing: true), 25)
    }

    func testNonFinitePositionsNeitherTrapNorFire() {
        var s = HeartbeatSchedule()
        XCTAssertNil(s.tick(position: .infinity, playing: true))
        XCTAssertNil(s.tick(position: .nan, playing: true))
        XCTAssertNil(s.tick(position: -.infinity, playing: true))
        XCTAssertEqual(s.mark(position: .nan), 0)
        XCTAssertEqual(s.mark(position: .infinity), 0)
        XCTAssertNil(s.tick(position: 14, playing: true))
        XCTAssertEqual(s.tick(position: 15, playing: true), 15)
    }

    func testNegativePositionIsNotTheFinishedMarker() {
        var s = HeartbeatSchedule()
        XCTAssertEqual(s.mark(position: -3), 0)
        XCTAssertNotEqual(s.mark(position: -1), HeartbeatSchedule.finished)
    }

    func testFinishedIsMinusOne() {
        XCTAssertEqual(HeartbeatSchedule.finished, -1)
    }
}
