import XCTest
import Dispatch
@testable import BiliShared

final class LockedTests: XCTestCase {
    func testConcurrentIncrements() {
        let counter = Locked(0)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in counter.withLock { $0 += 1 } }
        XCTAssertEqual(counter.current, 1000)
    }

    func testManualClock() {
        let manual = ManualClock(100)
        XCTAssertEqual(manual.clock.nowMs(), 100)
        manual.advance(50)
        XCTAssertEqual(manual.clock.nowMs(), 150)
        manual.set(10)
        XCTAssertEqual(manual.clock.nowMs(), 10)
    }
}
