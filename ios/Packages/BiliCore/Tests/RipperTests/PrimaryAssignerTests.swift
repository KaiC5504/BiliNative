import XCTest
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
}
