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

    func testRefusalCountsAgainstNobodyUntilSomethingDelivers() {
        let bans = BanList()
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        XCTAssertTrue(bans.allows(url("a", "f1")))
        bans.success(url: url("b", "f1"))
        XCTAssertFalse(bans.allowsNode(url("a", "f1")))
        bans.reset()
        XCTAssertTrue(bans.allows(url("a", "f1")))
    }
}
