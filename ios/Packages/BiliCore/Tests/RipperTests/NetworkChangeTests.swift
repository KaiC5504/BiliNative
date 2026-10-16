import XCTest
import BiliShared
import DevLog
@testable import Ripper

final class NetworkChangeTests: XCTestCase {
    let primary = "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv"

    func testResetHealthLiftsBackoffsAndKeepsSpeedsOnTheSameInterface() {
        let manual = ManualClock(100_000)
        let resolver = Resolver(primary: primary, backups: [], mode: .overseas, bans: BanList(), clock: manual.clock)
        let slow = resolver.urls()[0]
        let fast = resolver.urls()[1]
        resolver.failure(slow, status: 503, receivedBytes: 0)
        resolver.success(fast, bps: 2_000_000)
        XCTAssertFalse(resolver.ordered().contains(slow))

        resolver.resetHealth(clearMeasurements: false)
        XCTAssertTrue(resolver.ordered().contains(slow))
        XCTAssertEqual(resolver.speed(fast), 2_000_000)
    }

    func testResetHealthOnANewInterfaceForgetsSpeedsAndMeasuresWideAgain() {
        let manual = ManualClock(100_000)
        let resolver = Resolver(primary: primary, backups: [], mode: .overseas, bans: BanList(), clock: manual.clock)
        let fast = resolver.urls()[2]
        resolver.success(fast, bps: 9_000_000)
        for _ in 0..<4 { _ = resolver.rangeCandidates() }
        XCTAssertEqual(resolver.rangeCandidates().first, fast)

        resolver.resetHealth(clearMeasurements: true)
        XCTAssertEqual(resolver.speed(fast), 0)
        XCTAssertEqual(resolver.rangeCandidates().count, 4, "the first range after the change goes wide again")
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: fast) }?.state, "healthy")
    }

    /// A drop on the old path cuts every running copy and would otherwise count as damage at each of their offsets.
    func testResetHealthForgetsDamage() {
        let manual = ManualClock(100_000)
        let resolver = Resolver(primary: primary, backups: [], mode: .overseas, bans: BanList(), clock: manual.clock)
        let a = resolver.urls()[0]
        resolver.success(a, bps: 0)
        for block in Int64(0)..<2 {
            resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: block << 20 + 1_000, end: block << 20 + 9_999)!)
        }
        XCTAssertTrue(resolver.avoids(a, ByteRange(start: 1_000, end: 9_999)!))

        resolver.resetHealth(clearMeasurements: false)
        XCTAssertFalse(resolver.avoids(a, ByteRange(start: 1_000, end: 9_999)!))
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 2 << 20, end: 2 << 20 + 9_999)!)
        resolver.failure(a, status: nil, receivedBytes: 0, range: ByteRange(start: 2 << 20 + 5_000, end: 2 << 20 + 9_999)!)
        XCTAssertTrue(resolver.allows(a), "damage after the change is judged afresh")
    }

    func testSessionNetworkChangeClearsBansAndBackoffs() async {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(status: 503) }
        var config = TestEngine.config
        config.pieceRounds = 1
        let session = RipperSession(sources: [.video: (TestEngine.primary, [])], mode: .overseas, config: config,
                                    transport: SimCDN(size: 1_000_000, behaviors: behaviors), auto: nil, logger: Logger(session: "test"))
        do {
            for try await _ in session.read(.video, ByteRange(start: 2_000, end: 50_000)!) {}
            XCTFail("expected a failure")
        } catch {}
        XCTAssertTrue(session.stats().nodeStates.contains { $0.state == "banned" || $0.state == "blocked" })

        session.networkChanged(interfaceChanged: false)
        XCTAssertEqual(Set(session.stats().nodeStates.map(\.state)), ["untested"])
    }
}
