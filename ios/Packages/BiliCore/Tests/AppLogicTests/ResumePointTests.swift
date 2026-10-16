import XCTest
@testable import AppLogic

final class ResumePointTests: XCTestCase {
    func testResumeIgnoresOtherPartsTheEndAndFinished() {
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 65_000, lastPlayCid: 1, cid: 1, duration: 200), 65)
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 65_000, lastPlayCid: 2, cid: 1, duration: 200), 0)
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 196_000, lastPlayCid: 1, cid: 1, duration: 200), 0)
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: -1, lastPlayCid: 1, cid: 1, duration: 200), 0)
    }

    func testResumeNeedsMoreThanFiveSecondsLeft() {
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 195_000, lastPlayCid: 1, cid: 1, duration: 200), 0)
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 194_000, lastPlayCid: 1, cid: 1, duration: 200), 194)
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 0, lastPlayCid: 1, cid: 1, duration: 200), 0)
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 65_000, lastPlayCid: 1, cid: 1, duration: 0), 0)
    }

    func testResumeKeepsFractionalSeconds() {
        XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 65_500, lastPlayCid: 1, cid: 1, duration: 200), 65.5)
    }
}
