import XCTest
import BiliShared
@testable import Ripper

final class ResolverTests: XCTestCase {
    let primary = "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv"
    var manual: ManualClock!
    var resolver: Resolver!

    override func setUp() {
        manual = ManualClock(100_000)
        resolver = Resolver(primary: primary, backups: [], mode: .overseas, bans: BanList(), clock: manual.clock)
    }

    func node(_ index: Int) -> String { resolver.urls()[index] }

    func testOrderedRotates() {
        let first = resolver.ordered()
        let second = resolver.ordered()
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(Array(second), Array(first[1...] + first[..<1]))
    }

    func testFailureBacksOff() {
        let a = node(0)
        resolver.failure(a, status: 503, receivedBytes: 0)
        XCTAssertFalse(resolver.ordered().contains(a))
        manual.advance(6_001)
        XCTAssertTrue(resolver.ordered().contains(a))
    }

    func testSpeedIsAveragedAndExpires() {
        let a = node(0)
        resolver.success(a, bps: 1_000_000)
        XCTAssertEqual(resolver.speed(a), 1_000_000)
        resolver.success(a, bps: 2_000_000)
        XCTAssertEqual(resolver.speed(a), 1_350_000, accuracy: 0.1)
        manual.advance(90_001)
        XCTAssertEqual(resolver.speed(a), 0)
    }

    func testSampleMeasuresWithoutProvingTheAddress() {
        let a = node(1)
        resolver.sample(a, bps: 500_000)
        XCTAssertEqual(resolver.speed(a), 500_000)
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: a) }?.state, "untested")
    }

    func testNewSignatureKeepsTheRouteSpeed() {
        let a = node(0)
        resolver.success(a, bps: 3_000_000)
        resolver.replaceURLs(primary: primary.replacingOccurrences(of: "deadline=9", with: "deadline=99"), backups: [])
        let renewed = node(0)
        XCTAssertNotEqual(renewed, a)
        XCTAssertEqual(resolver.speed(renewed), 3_000_000)
    }

    func testRangeCandidatesWarmUpThenPreferMeasured() {
        XCTAssertEqual(resolver.rangeCandidates().count, 4)
        let fast = node(2)
        resolver.success(fast, bps: 9_000_000)
        for _ in 0..<3 { _ = resolver.rangeCandidates() }
        let after = resolver.rangeCandidates()
        XCTAssertEqual(after.first, fast)
        XCTAssertGreaterThanOrEqual(after.count, 3)
    }

    func testStatusShowsBans() {
        let a = node(0)
        resolver.failure(a, status: nil, receivedBytes: 0)
        resolver.failure(a, status: nil, receivedBytes: 0)
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: a) }?.state, "banned")
        XCTAssertFalse(resolver.urls().contains(a))
    }
}
