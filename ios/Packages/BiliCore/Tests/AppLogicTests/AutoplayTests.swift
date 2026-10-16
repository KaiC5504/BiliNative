import XCTest
@testable import AppLogic

final class AutoplayTests: XCTestCase {
    private let a = PlayItem(bvid: "A", cid: 1)
    private let b = PlayItem(bvid: "B", cid: 2)
    private let c = PlayItem(bvid: "C", cid: 3)

    func testAutoplayWalksSectionsAndStopsAtTheEnd() {
        XCTAssertEqual(Autoplay.next(after: a, parts: [a], episodes: [a, b, c], autoplay: true, loop: .none), .play(b))
        XCTAssertEqual(Autoplay.next(after: c, parts: [c], episodes: [a, b, c], autoplay: true, loop: .none), .stop)
        XCTAssertEqual(Autoplay.next(after: c, parts: [c], episodes: [a, b, c], autoplay: false, loop: .list), .play(a))
        XCTAssertEqual(Autoplay.next(after: b, parts: [b], episodes: [a, b, c], autoplay: false, loop: .none), .stop)
        XCTAssertEqual(Autoplay.next(after: b, parts: [b], episodes: [a, b, c], autoplay: true, loop: .single), .replay)
    }

    func testAutoplayPrefersTheNextPart() {
        let p1 = PlayItem(bvid: "A", cid: 11), p2 = PlayItem(bvid: "A", cid: 12)
        XCTAssertEqual(Autoplay.next(after: p1, parts: [p1, p2], episodes: [], autoplay: true, loop: .none), .play(p2))
        XCTAssertEqual(Autoplay.next(after: p1, parts: [p1, p2], episodes: [p1, b], autoplay: true, loop: .none), .play(p2))
        XCTAssertEqual(Autoplay.next(after: p1, parts: [p1, p2], episodes: [p1, b], autoplay: false, loop: .list), .play(p2))
    }

    func testLastPartMovesOnToTheNextEpisodeByBvid() {
        let p1 = PlayItem(bvid: "A", cid: 11), p2 = PlayItem(bvid: "A", cid: 12)
        XCTAssertEqual(Autoplay.next(after: p2, parts: [p1, p2], episodes: [p1, b, c], autoplay: true, loop: .none), .play(b))
    }

    func testEpisodeIsFoundByCidBeforeBvid() {
        let e1 = PlayItem(bvid: "A", cid: 1), e2 = PlayItem(bvid: "A", cid: 2), e3 = PlayItem(bvid: "A", cid: 3)
        XCTAssertEqual(Autoplay.next(after: e2, parts: [e2], episodes: [e1, e2, e3], autoplay: true, loop: .none), .play(e3))
    }

    func testListLoopWrapsToTheFirstPartWithoutEpisodes() {
        let p1 = PlayItem(bvid: "A", cid: 11), p2 = PlayItem(bvid: "A", cid: 12)
        XCTAssertEqual(Autoplay.next(after: p2, parts: [p1, p2], episodes: [], autoplay: false, loop: .list), .play(p1))
    }

    func testListLoopOfOneItemReplays() {
        XCTAssertEqual(Autoplay.next(after: a, parts: [a], episodes: [], autoplay: false, loop: .list), .replay)
        XCTAssertEqual(Autoplay.next(after: a, parts: [a], episodes: [a], autoplay: true, loop: .list), .replay)
    }

    func testListLoopOutsideTheCollectionStaysWithTheVideo() {
        let x = PlayItem(bvid: "X", cid: 9)
        XCTAssertEqual(Autoplay.next(after: x, parts: [x], episodes: [a, b, c], autoplay: true, loop: .list), .replay)
    }

    func testNothingAfterAStandaloneVideoStops() {
        XCTAssertEqual(Autoplay.next(after: a, parts: [a], episodes: [], autoplay: true, loop: .none), .stop)
        XCTAssertEqual(Autoplay.next(after: a, parts: [], episodes: [], autoplay: true, loop: .none), .stop)
    }

    func testSingleLoopReplaysEvenWithAutoplayOff() {
        XCTAssertEqual(Autoplay.next(after: a, parts: [a], episodes: [a, b], autoplay: false, loop: .single), .replay)
    }

    func testLoopModeRawValues() {
        XCTAssertEqual(LoopMode.allCases.map(\.rawValue), ["single", "list", "none"])
    }
}
