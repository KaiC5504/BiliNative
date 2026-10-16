import XCTest
@testable import Danmaku

final class LaneLayoutTests: XCTestCase {
    func testScrollLaneWaitsUntilTheLastOneHasEntered() {
        var layout = LaneLayout(lanes: 3, width: 400, scrollDuration: 8)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 0), 0)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 0.5), 1)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 2.0), 0)
    }

    func testFastLongDanmakuDoesNotCatchASlowShortOne() {
        var layout = LaneLayout(lanes: 2, width: 400, scrollDuration: 8)
        XCTAssertEqual(layout.place(.scroll, width: 20, at: 0), 0)
        // The long one has room to enter at 0.5 s, but at 100 pt/s it would reach the short one before it leaves.
        XCTAssertEqual(layout.place(.scroll, width: 400, at: 0.5), 1)
    }

    func testScrollDropsWhenEveryLaneIsBusy() {
        var layout = LaneLayout(lanes: 2, width: 400, scrollDuration: 8)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 0), 0)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 0.1), 1)
        XCTAssertNil(layout.place(.scroll, width: 100, at: 0.2))
    }

    func testStaticLanesFromTheirEdgesAndDropWhenFull() {
        var layout = LaneLayout(lanes: 2, width: 400, scrollDuration: 8)
        XCTAssertEqual(layout.place(.top, width: 50, at: 0), 0)
        XCTAssertEqual(layout.place(.top, width: 50, at: 1), 1)
        XCTAssertNil(layout.place(.top, width: 50, at: 2))
        XCTAssertEqual(layout.place(.bottom, width: 50, at: 2), 1)
        XCTAssertEqual(layout.place(.bottom, width: 50, at: 2), 0)
        XCTAssertNil(layout.place(.bottom, width: 50, at: 3))
    }

    func testStaticLaneFreesAfterItsDuration() {
        var layout = LaneLayout(lanes: 1, width: 400, scrollDuration: 8, staticDuration: 4)
        XCTAssertEqual(layout.place(.top, width: 50, at: 10), 0)
        XCTAssertNil(layout.place(.top, width: 50, at: 13.9))
        XCTAssertEqual(layout.place(.top, width: 50, at: 14), 0)
    }

    func testResetClearsEveryLaneAndTakesNewGeometry() {
        var layout = LaneLayout(lanes: 1, width: 400, scrollDuration: 8)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 0), 0)
        XCTAssertEqual(layout.place(.top, width: 100, at: 0), 0)
        XCTAssertNil(layout.place(.scroll, width: 100, at: 0.1))
        layout.reset(lanes: 2, width: 800, scrollDuration: 6)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 0.1), 0)
        XCTAssertEqual(layout.place(.scroll, width: 100, at: 0.1), 1)
        XCTAssertEqual(layout.place(.top, width: 100, at: 0.1), 0)
    }

    func testZeroLanesPlacesNothing() {
        var layout = LaneLayout(lanes: 0, width: 400, scrollDuration: 8)
        XCTAssertNil(layout.place(.scroll, width: 10, at: 0))
        XCTAssertNil(layout.place(.top, width: 10, at: 0))
        XCTAssertNil(layout.place(.bottom, width: 10, at: 0))
    }

    func testHeavySegmentFiltersAndLaysOutQuickly() {
        let words = ["哈哈哈", "前方高能", "666", "awsl", "名场面", "好家伙", "泪目", "太强了"]
        var elems: [DanmakuElem] = []
        elems.reserveCapacity(20_000)
        var seed: UInt64 = 42
        func random(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let modes = [1, 1, 1, 1, 4, 5, 6, 7]
        for i in 0..<20_000 {
            elems.append(DanmakuElem(id: Int64(i), progressMs: Int64(random(360_000)), mode: modes[random(modes.count)],
                                     color: random(5) == 0 ? 0xFF0000 : 0xFFFFFF, midHash: String(random(500), radix: 16),
                                     content: words[random(words.count)] + String(random(3_000))))
        }
        let options = DanmakuFilterOptions(blockFixed: true, blockScroll: false, blockColored: true, blockAdvanced: true,
                                           blockCount: false, dedupe: true, hideBottom: true)
        let rules = [BlockRule(id: 1, kind: .keyword, filter: "泪目1"), BlockRule(id: 2, kind: .regex, filter: "/awsl2\\d+/"),
                     BlockRule(id: 3, kind: .user, filter: "1f4")]

        let started = Date()
        let shown = DanmakuFilter.apply(elems, options: options, rules: rules, ownHash: "abc")
        var layout = LaneLayout(lanes: 30, width: 800, scrollDuration: 7)
        var placed = 0
        for item in shown where layout.place(.scroll, width: Double(item.text.count) * 25, at: Double(item.elem.progressMs) / 1_000) != nil {
            placed += 1
        }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThan(shown.count, 1_000)
        XCTAssertGreaterThan(placed, 0)
        XCTAssertLessThan(elapsed, 1.0)
    }
}
