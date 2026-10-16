import XCTest
@testable import AppLogic

final class GestureMathTests: XCTestCase {
    func testConstants() {
        XCTAssertEqual(GestureMath.seekSecondsPerWidth, 90)
        XCTAssertEqual(GestureMath.axisLockDistance, 10)
        XCTAssertEqual(GestureMath.edgeInset, 25)
    }

    func testAxisLocksAfterTenPoints() {
        XCTAssertNil(GestureMath.axis(dx: 6, dy: 6))
        XCTAssertNil(GestureMath.axis(dx: 0, dy: 9.99))
        XCTAssertEqual(GestureMath.axis(dx: 8, dy: -9), .vertical)
        XCTAssertEqual(GestureMath.axis(dx: -12, dy: 3), .horizontal)
        XCTAssertEqual(GestureMath.axis(dx: 0, dy: 10), .vertical)
    }

    func testAxisTiesAreHorizontal() {
        XCTAssertEqual(GestureMath.axis(dx: 8, dy: 8), .horizontal)
        XCTAssertEqual(GestureMath.axis(dx: -8, dy: 8), .horizontal)
    }

    func testSeekIs90SecondsPerWidthAndClamped() {
        XCTAssertEqual(GestureMath.seekTarget(start: 100, dx: 200, width: 400, duration: 600), 145)
        XCTAssertEqual(GestureMath.seekTarget(start: 10, dx: -400, width: 400, duration: 600), 0)
        XCTAssertEqual(GestureMath.seekTarget(start: 590, dx: 400, width: 400, duration: 600), 600)
    }

    func testSeekWithoutAWidthOrDurationStaysPut() {
        XCTAssertEqual(GestureMath.seekTarget(start: 30, dx: 50, width: 0, duration: 600), 30)
        XCTAssertEqual(GestureMath.seekTarget(start: 30, dx: 50, width: 400, duration: 0), 0)
    }

    func testLevelUpRaisesAndClamps() {
        XCTAssertEqual(GestureMath.level(start: 0.5, dy: -100, height: 400), 0.75)
        XCTAssertEqual(GestureMath.level(start: 0.9, dy: -400, height: 400), 1)
        XCTAssertEqual(GestureMath.level(start: 0.2, dy: 400, height: 400), 0)
        XCTAssertEqual(GestureMath.level(start: 0.5, dy: 100, height: 400), 0.25)
    }

    func testLevelWithoutAHeightKeepsTheStart() {
        XCTAssertEqual(GestureMath.level(start: 0.4, dy: -50, height: 0), 0.4)
    }
}
