import XCTest
@testable import Ripper

final class BanListTests: XCTestCase {
    func url(_ node: String, _ file: String) -> String { "https://\(node).bilivideo.com/upgcxcode/\(file).m4s?deadline=1" }

    func testTwoSilentFailuresBanTheNode() {
        let bans = BanList()
        XCTAssertFalse(bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil))
        XCTAssertTrue(bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil))
        XCTAssertFalse(bans.allows(url("a", "f2")))
        XCTAssertEqual(bans.bannedNodes(), ["a.bilivideo.com"])
    }

    func testPartialTransfersAreNotStrikes() {
        let bans = BanList()
        bans.record(url: url("a", "f1"), receivedBytes: 10, status: nil)
        bans.record(url: url("a", "f1"), receivedBytes: 10, status: nil)
        XCTAssertTrue(bans.allows(url("a", "f1")))
    }

    func testRefusalByAGoodNodeBlamesTheAddress() {
        let bans = BanList()
        bans.success(url: url("a", "f1"))
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        XCTAssertFalse(bans.allows(url("b", "f2")))
        XCTAssertTrue(bans.allows(url("a", "f1")))
    }

    func testRefusalOfAGoodAddressByAGoodNodeBlamesOnlyThePair() {
        let bans = BanList()
        var kinds: [BanList.BanKind] = []
        bans.onBan = { _, _, kind in kinds.append(kind) }
        bans.success(url: url("a", "f1"))
        bans.success(url: url("b", "f2"))
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        XCTAssertFalse(bans.allows(url("a", "f2")))
        XCTAssertTrue(bans.allows(url("b", "f2")))
        XCTAssertTrue(bans.allows(url("a", "f1")))
        XCTAssertEqual(kinds, [.pair])
    }

    func testSuccessLiftsABanCausedBySilentFailures() {
        let bans = BanList()
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil)
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil)
        XCTAssertFalse(bans.allowsNode(url("a", "f2")))
        bans.success(url: url("a", "f2"))
        XCTAssertTrue(bans.allowsNode(url("a", "f2")))
        XCTAssertTrue(bans.allows(url("a", "f1")))
        XCTAssertEqual(bans.bannedNodes(), [])
    }

    func testSuccessKeepsAnAddressBanFromRefusals() {
        let bans = BanList()
        bans.success(url: url("a", "f1"))
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        XCTAssertFalse(bans.allowsAddress(url("b", "f2")))
        bans.success(url: url("a", "f3"))
        XCTAssertFalse(bans.allowsAddress(url("b", "f2")))
        XCTAssertFalse(bans.allows(url("a", "f2")))
        XCTAssertTrue(bans.allows(url("a", "f3")))
    }

    func testRebanAfterHealingIsReportedAgain() {
        let bans = BanList()
        var reported: [String] = []
        bans.onBan = { node, _, kind in if kind == .node { reported.append(node) } }
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil)
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil)
        bans.success(url: url("a", "f1"))
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil)
        XCTAssertTrue(bans.allowsNode(url("a", "f1")))
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil)
        XCTAssertFalse(bans.allowsNode(url("a", "f1")))
        XCTAssertEqual(reported, ["a.bilivideo.com", "a.bilivideo.com"])
    }

    func testRefusalCountsAgainstNobodyUntilSomethingDelivers() {
        let bans = BanList()
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        XCTAssertTrue(bans.allows(url("a", "f1")))
        bans.success(url: url("b", "f1"))
        XCTAssertFalse(bans.allows(url("a", "f1")))
        bans.reset()
        XCTAssertTrue(bans.allows(url("a", "f1")))
    }

    func testRefusalByANodeThatHasNotDeliveredDropsOnlyThePair() {
        let bans = BanList()
        var reports: [String] = []
        bans.onBan = { node, strikes, kind in reports.append("\(node) \(strikes) \(kind)") }
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        bans.success(url: url("b", "f1"))
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        XCTAssertFalse(bans.allows(url("a", "f1")))
        XCTAssertTrue(bans.allowsNode(url("a", "f2")))
        XCTAssertTrue(bans.allows(url("a", "f2")))
        XCTAssertTrue(bans.allowsAddress(url("b", "f1")))
        XCTAssertEqual(reports, ["a.bilivideo.com 2 pair"], "the pair is reported against the refusing node")
        bans.success(url: url("a", "f2"))
        XCTAssertFalse(bans.allows(url("a", "f1")))
        XCTAssertTrue(bans.allows(url("a", "f2")))
    }

    func testNodeRefusingTwoAddressesOthersServeIsBanned() {
        let bans = BanList()
        bans.success(url: url("b", "f1"))
        bans.success(url: url("b", "f2"))
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        XCTAssertTrue(bans.allowsNode(url("a", "f3")))
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        XCTAssertFalse(bans.allowsNode(url("a", "f3")))
        XCTAssertEqual(bans.bannedNodes(), ["a.bilivideo.com"])
    }
}
