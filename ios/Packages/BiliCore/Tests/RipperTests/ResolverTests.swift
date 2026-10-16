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

    func testStatusShowsPairBans() {
        let a = node(0)
        resolver.success(a, bps: 0)
        resolver.failure(a, status: 403, receivedBytes: 0)
        resolver.failure(a, status: 403, receivedBytes: 0)
        XCTAssertTrue(resolver.bans?.allowsNode(a) ?? false)
        manual.advance(60_001)
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: a) }?.state, "banned")
    }

    /// Akamai, 2026-10-16: its copy of one file lacked 109972 through the end of the first MiB. A request crossing
    /// 109972 was cut there; one starting in the gap got no response at all; everything else was served.
    func testCutCopyIsAvoidedOverItsBlockWithoutStrikesOrBackoff() {
        let a = node(0)
        let b = node(1)
        resolver.success(a, bps: 0)
        resolver.failure(a, status: nil, receivedBytes: 9_972, range: ByteRange(start: 100_000, end: 199_999)!)
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 300_000, end: 399_999)!)
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 400_000, end: 499_999)!)
        XCTAssertTrue(resolver.avoids(a, ByteRange(start: 100_000, end: 199_999)!))
        XCTAssertTrue(resolver.avoids(a, ByteRange(start: 109_972, end: 109_972)!))
        XCTAssertTrue(resolver.avoids(a, ByteRange(start: 1_000_000, end: 1_100_000)!), "the rest of the block")
        XCTAssertFalse(resolver.avoids(a, ByteRange(start: 0, end: 109_971)!))
        XCTAssertFalse(resolver.avoids(a, ByteRange(start: 1_048_576, end: 2_000_000)!))
        XCTAssertFalse(resolver.avoids(b, ByteRange(start: 100_000, end: 199_999)!))
        XCTAssertTrue(resolver.allows(a))
        XCTAssertTrue(resolver.ordered().contains(a), "no backoff")
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: a) }?.state, "healthy")
    }

    func testDamageIsPerFile() {
        let a = node(0)
        resolver.success(a, bps: 0)
        resolver.failure(a, status: nil, receivedBytes: 10, range: ByteRange(start: 100_000, end: 199_999)!)
        let other = Resolver(primary: primary.replacingOccurrences(of: "v.m4s", with: "a.m4s"), backups: [], mode: .overseas,
                             bans: resolver.bans, clock: manual.clock)
        XCTAssertFalse(other.avoids(other.urls()[0], ByteRange(start: 100_000, end: 199_999)!))
    }

    func testDamageInAThirdBlockIsStruckAsBefore() {
        let a = node(0)
        resolver.success(a, bps: 0)
        for block in Int64(0)..<2 {
            resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: block << 20 + 5_000, end: block << 20 + 9_999)!)
            resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: block << 20 + 6_000, end: block << 20 + 9_999)!)
        }
        XCTAssertTrue(resolver.allows(a))
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 2 << 20, end: 2 << 20 + 9_999)!)
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 3 << 20, end: 3 << 20 + 9_999)!)
        XCTAssertFalse(resolver.allows(a))
    }

    func testEmptyRepliesFromANodeThatNeverDeliveredAreStruckAsBefore() {
        let a = node(0)
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 300_000, end: 399_999)!)
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 400_000, end: 499_999)!)
        XCTAssertFalse(resolver.allows(a))
        XCTAssertFalse(resolver.avoids(a, ByteRange(start: 300_000, end: 399_999)!))
    }

    func testTimeoutsAreNotPositional() {
        let a = node(0)
        resolver.success(a, bps: 0)
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 300_000, end: 399_999)!, timedOut: true)
        XCTAssertFalse(resolver.avoids(a, ByteRange(start: 300_000, end: 399_999)!))
        XCTAssertFalse(resolver.ordered().contains(a))
    }

    func testStatusShowsBans() {
        let a = node(0)
        resolver.failure(a, status: nil, receivedBytes: 0)
        resolver.failure(a, status: nil, receivedBytes: 0)
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: a) }?.state, "banned")
        XCTAssertFalse(resolver.urls().contains(a))
    }
}
