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

    /// Two Akamai requests lost their connection 2 ms apart and banned the fastest node for the rest of the video
    /// (phone, 2026-10-17).
    func testConnectionsLostAtTheSameMomentAreOneStrike() {
        let bans = BanList()
        let a = url("a", "f1"), b = url("b", "f1")
        bans.record(url: a, receivedBytes: 0, status: nil, lostAt: 1_000)
        bans.record(url: a, receivedBytes: 0, status: nil, lostAt: 1_002)
        bans.record(url: b, receivedBytes: 0, status: nil, lostAt: 1_100)
        XCTAssertTrue(bans.allows(a))
        XCTAssertTrue(bans.allows(b), "lost at the same moment as a's")
        bans.record(url: a, receivedBytes: 0, status: nil, lostAt: 1_600)
        XCTAssertFalse(bans.allows(a), "the next round's loss is a second event")
        XCTAssertTrue(bans.allows(b))
    }

    func testTheMomentDoesNotStretchWhileLossesKeepComing() {
        let bans = BanList()
        let a = url("a", "f1")
        for lostAt in stride(from: 1_000.0, through: 1_300, by: 100) { bans.record(url: a, receivedBytes: 0, status: nil, lostAt: lostAt) }
        XCTAssertFalse(bans.allows(a), "losses at 1000 and 1300 ms are two moments")
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

    /// One list serves both tracks, and a new signature is a new address: the video and audio files, before
    /// and after a refresh, are four addresses Akamai refuses with `os=cosovbv` while it serves `os=akam`.
    func testRefusingManyServedAddressesNeverBansTheNode() {
        func akamai(_ file: String, _ os: String, deadline: Int = 9) -> String {
            "https://upos-hz-mirrorakam.akamaized.net/upgcxcode/\(file).m4s?deadline=\(deadline)&os=\(os)"
        }
        func mirror(_ file: String, _ os: String, deadline: Int = 9) -> String {
            akamai(file, os, deadline: deadline).replacingOccurrences(of: "upos-hz-mirrorakam.akamaized.net", with: "b.bilivideo.com")
        }
        let bans = BanList()
        for deadline in [9, 99] {
            for file in ["video", "audio"] {
                bans.success(url: mirror(file, "cosovbv", deadline: deadline))
                bans.record(url: akamai(file, "cosovbv", deadline: deadline), receivedBytes: 0, status: 403)
                bans.record(url: akamai(file, "cosovbv", deadline: deadline), receivedBytes: 0, status: 403)
                XCTAssertFalse(bans.allows(akamai(file, "cosovbv", deadline: deadline)))
            }
        }
        XCTAssertTrue(bans.allowsNode(akamai("video", "akam")))
        XCTAssertTrue(bans.allows(akamai("video", "akam")))
        XCTAssertTrue(bans.allows(akamai("audio", "akam")))
        XCTAssertEqual(bans.bannedNodes(), [])
    }
}
