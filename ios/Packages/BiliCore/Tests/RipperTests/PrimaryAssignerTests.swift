import XCTest
import Foundation
import BiliShared
@testable import Ripper

final class PrimaryAssignerTests: XCTestCase {
    final class Key {}

    func testWeightedTurnsAndTrialsAtTheEnd() {
        let speeds = ["A": 10.0, "B": 5.0, "C": 0.0]
        let result = PrimaryAssigner().assign(urls: ["A", "B", "C"], count: 8, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(Key()))
        XCTAssertEqual(result, ["A", "B", "A", "A", "B", "A", "C", "C"])
    }

    func testVerySlowNodeGetsNothing() {
        let speeds = ["A": 120.0, "B": 5.0]
        XCTAssertEqual(PrimaryAssigner().assign(urls: ["A", "B"], count: 4, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(Key())),
                       ["A", "A", "A", "A"])
    }

    func testAFullNodeSitsOutWhileAnotherHasRoom() {
        let a = "https://a.example/v", b = "https://b.example/v"
        let speeds = [a: 10.0, b: 5.0]
        // a has room for two more pieces.
        let result = PrimaryAssigner().assign(urls: [a, b], count: 6, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(Key()),
                                              isFull: { url, placed in url == a && placed >= 2 })
        XCTAssertEqual(result, [a, b, a, b, b, b])
        let unmeasured = PrimaryAssigner().assign(urls: [a, b], count: 4, speed: { _ in 0 }, trialKey: ObjectIdentifier(Key()),
                                                  isFull: { url, placed in url == a && placed >= 1 })
        XCTAssertEqual(unmeasured, [a, b, b, b])
    }

    func testTurnsGoOnAsUsualWhenEveryNodeIsFull() {
        let speeds = ["A": 10.0, "B": 5.0, "C": 0.0]
        let result = PrimaryAssigner().assign(urls: ["A", "B", "C"], count: 8, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(Key()),
                                              isFull: { _, _ in true })
        XCTAssertEqual(result, ["A", "B", "A", "A", "B", "A", "C", "C"])
    }

    func testRoundRobinWithoutMeasurementsRotatesPerRange() {
        let assigner = PrimaryAssigner()
        let key = ObjectIdentifier(Key())
        XCTAssertEqual(assigner.assign(urls: ["a", "b", "c"], count: 4, speed: { _ in 0 }, trialKey: key), ["a", "b", "c", "a"])
        XCTAssertEqual(assigner.assign(urls: ["a", "b", "c"], count: 4, speed: { _ in 0 }, trialKey: key), ["b", "c", "a", "b"])
    }

    func testSmallRangesGiveAnUnknownNodeATrialEveryFourth() {
        let assigner = PrimaryAssigner()
        let owner = Key()
        let speeds = ["A": 10.0]
        var results: [[String]] = []
        for _ in 0..<4 {
            results.append(assigner.assign(urls: ["A", "C"], count: 2, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(owner)))
        }
        XCTAssertEqual(results, [["A", "A"], ["A", "A"], ["A", "A"], ["A", "C"]])
    }

    func testConcurrentRangesNeverLoseATrialTurn() {
        let assigner = PrimaryAssigner()
        let owner = Key()
        let key = ObjectIdentifier(owner)
        let trials = Locked(0)
        DispatchQueue.concurrentPerform(iterations: 400) { _ in
            let result = assigner.assign(urls: ["A", "C"], count: 2, speed: { $0 == "A" ? 10 : 0 }, trialKey: key)
            if result.last == "C" { trials.withLock { $0 += 1 } }
        }
        XCTAssertEqual(trials.current, 100)
        withExtendedLifetime(owner) {}
    }
}
