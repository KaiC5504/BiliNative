import XCTest
@testable import Danmaku

final class TimelineTests: XCTestCase {
    private func items(at times: [Int64]) -> [DisplayDanmaku] {
        times.map { DisplayDanmaku(elem: makeElem("t\($0)", at: $0), text: "t\($0)", isOwn: false) }
    }

    func testSeekBackReemitsOnceAndJumpSkips() {
        var t = DanmakuTimeline(); t.add(items(at: [500, 1_500, 2_500]))
        XCTAssertEqual(t.advance(to: 600).count, 1); XCTAssertEqual(t.advance(to: 1_600).count, 1)
        t.seek(to: 0); XCTAssertEqual(t.advance(to: 600).count, 1)
        XCTAssertEqual(t.advance(to: 3_000).count, 0)   // a 2 400 ms jump is a seek
    }

    func testAdvanceReturnsEachItemOnceInOrder() {
        var t = DanmakuTimeline(); t.add(items(at: [300, 100, 200]))
        XCTAssertEqual(t.advance(to: 250).map(\.text), ["t100", "t200"])
        XCTAssertEqual(t.advance(to: 250).count, 0)
        XCTAssertEqual(t.advance(to: 350).map(\.text), ["t300"])
        XCTAssertEqual(t.advance(to: 900).count, 0)
    }

    func testAStepBackwardsIsASeek() {
        var t = DanmakuTimeline(); t.add(items(at: [100, 200, 300]))
        XCTAssertEqual(t.advance(to: 350).count, 3)
        XCTAssertEqual(t.advance(to: 150).count, 0)
        XCTAssertEqual(t.advance(to: 250).map(\.text), ["t200"])
    }

    func testFirstAdvanceAfterAStartMidVideoSkipsEarlierItems() {
        var t = DanmakuTimeline(); t.add(items(at: [100, 60_000, 60_500]))
        XCTAssertEqual(t.advance(to: 60_000).count, 0)
        XCTAssertEqual(t.advance(to: 60_600).map(\.text), ["t60500"])
    }

    func testItemsAtTimeZeroAreEmittedByTheFirstAdvance() {
        var t = DanmakuTimeline(); t.add(items(at: [0, 50]))
        XCTAssertEqual(t.advance(to: 100).map(\.text), ["t0", "t50"])
    }

    func testItemsAddedBehindThePlayheadWaitForASeek() {
        var t = DanmakuTimeline(); t.add(items(at: [1_000]))
        XCTAssertEqual(t.advance(to: 900).count, 0)
        XCTAssertEqual(t.advance(to: 1_100).count, 1)
        t.add(items(at: [500, 1_050, 1_200]))
        XCTAssertEqual(t.advance(to: 1_300).map(\.text), ["t1200"])
        t.seek(to: 0)
        XCTAssertEqual(t.advance(to: 600).map(\.text), ["t500"])
    }

    func testSameMillisecondKeepsArrivalOrder() {
        var t = DanmakuTimeline()
        t.add([DisplayDanmaku(elem: makeElem("a", at: 100), text: "a", isOwn: false)])
        t.add([DisplayDanmaku(elem: makeElem("b", at: 100), text: "b", isOwn: false)])
        XCTAssertEqual(t.advance(to: 200).map(\.text), ["a", "b"])
    }
}
