import XCTest
import BiliShared
@testable import Ripper

final class AutoConcurrencyTests: XCTestCase {
    var manual: ManualClock!
    var auto: AutoConcurrency!

    override func setUp() {
        manual = ManualClock(100_000)
        auto = AutoConcurrency(clock: manual.clock)
    }

    func testNewSessionStartsAt16AndComesBackWhenAhead() {
        XCTAssertEqual(auto.threads, 8)
        auto.newSession()
        XCTAssertEqual(auto.threads, 16)
        XCTAssertTrue(auto.status().inStartup)
        manual.advance(3_000)
        auto.buffer(ahead: 20, playing: true)
        XCTAssertEqual(auto.threads, 12)
        manual.advance(3_000)
        auto.buffer(ahead: 20, playing: true)
        XCTAssertEqual(auto.threads, 8)
        XCTAssertFalse(auto.status().inStartup)
    }

    func testStallClimbsAndRespectsCooldown() {
        auto.newSession()
        XCTAssertFalse(auto.stall())
        manual.advance(3_000)
        XCTAssertTrue(auto.stall())
        XCTAssertEqual(auto.threads, 24)
    }

    func testPushbackStepsDownAndBlocksThatLevel() {
        auto.newSession()
        manual.advance(3_000)
        auto.stall()
        XCTAssertEqual(auto.threads, 24)
        XCTAssertTrue(auto.pushback(status: 429))
        XCTAssertEqual(auto.threads, 16)
        manual.advance(3_000)
        XCTAssertFalse(auto.stall())
        XCTAssertEqual(auto.threads, 16)
        manual.advance(180_001)
        XCTAssertTrue(auto.stall())
        XCTAssertEqual(auto.threads, 24)
    }

    func testFruitlessTrialIsTakenBack() {
        auto.demand(active: 8, limit: 8, queued: 4)
        for _ in 0..<10 {
            auto.delivered(1_000_000)
            manual.advance(500)
        }
        XCTAssertTrue(auto.stall())
        XCTAssertEqual(auto.threads, 12)
        for _ in 0..<21 {
            auto.delivered(200_000)
            manual.advance(500)
        }
        XCTAssertEqual(auto.threads, 8)
    }

    func testLowBufferPressureClimbs() {
        for step in [0.0, 600, 600, 1_100] {
            manual.advance(step)
            auto.activity()
            auto.buffer(ahead: 3, playing: true)
        }
        XCTAssertEqual(auto.threads, 12)
    }

    func testOnChangeReportsSteps() {
        var seen: [Int] = []
        auto.onChange = { threads, _, _ in seen.append(threads) }
        auto.newSession()
        XCTAssertEqual(seen, [16])
    }

    func testOnChangeRunsOutsideTheLock() {
        var seen: [Int] = []
        auto.onChange = { [unowned auto] threads, _, _ in seen.append(auto!.threads * 100 + threads) }
        auto.newSession()
        XCTAssertEqual(seen, [1616])
    }
}
