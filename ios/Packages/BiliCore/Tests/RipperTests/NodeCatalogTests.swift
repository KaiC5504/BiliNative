import XCTest
@testable import Ripper

final class NodeCatalogTests: XCTestCase {
    let primary = "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv&upsig=x"
    let backup = "https://upos-sz-mirrorali.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=alibv"

    func testOverseasSwapsTheSignedAddressOntoOverseasNodes() {
        let urls = NodeCatalog.representationURLs(primary: primary, backups: [backup], mode: .overseas, policy: .bilibili)
        XCTAssertEqual(urls.map(NodeCatalog.host(of:)), NodeCatalog.overseas)
        XCTAssertTrue(urls.allSatisfy { NodeCatalog.address(of: $0) == "/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv&upsig=x" })
    }

    func testMainlandKeepsOriginalsFirstAndDeduplicates() {
        let urls = NodeCatalog.representationURLs(primary: primary, backups: [backup], mode: .mainland, policy: .bilibili)
        XCTAssertEqual(Array(urls.prefix(2)), [primary, backup])
        XCTAssertEqual(urls.count, 9)
        XCTAssertEqual(Set(urls).count, urls.count)
    }

    func testAkamaiOnlyAddressesBecomeDonors() {
        let akamai = "https://upos-hz-mirrorakam.akamaized.net/upgcxcode/1/2/3/v.m4s?deadline=9&os=akam&hdnts=x"
        let urls = NodeCatalog.representationURLs(primary: akamai, backups: [], mode: .overseas, policy: .bilibili)
        XCTAssertEqual(urls.first, akamai)
        XCTAssertEqual(urls.count, 1 + NodeCatalog.overseas.count)
        XCTAssertNil(NodeCatalog.swapHost(akamai, to: NodeAddress(host: "upos-sz-mirrorcosov.bilivideo.com")))
    }

    func testSwapClearsNonStandardPort() {
        let withPort = "https://upos-sz-mirrorcos.bilivideo.com:4483/upgcxcode/v.m4s?deadline=9"
        let swapped = NodeCatalog.swapHost(withPort, to: NodeAddress(host: "upos-sz-mirrorcosov.bilivideo.com"))
        XCTAssertEqual(swapped, "https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/v.m4s?deadline=9")
    }

    func testSwapKeepsSignedPathAndQueryByteForByte() {
        let query = "deadline=9&gen=playurlv3&upsig=a%2Fb%2Bc+d%3D%3D&hdnts=exp%3D1~acl%3D%2F*&e=ig8euxZM2rNcNbdlhoNvNC8BqJIzNbfq"
        let path = "/upgcxcode/1/2/3%2F4/v%20x.m4s"
        let signed = "https://upos-sz-mirrorcos.bilivideo.com\(path)?\(query)"
        let swapped = NodeCatalog.swapHost(signed, to: NodeAddress(host: "upos-sz-mirrorcosov.bilivideo.com"))
        XCTAssertEqual(swapped, "https://upos-sz-mirrorcosov.bilivideo.com\(path)?\(query)")
        XCTAssertEqual(NodeCatalog.address(of: signed), "\(path)?\(query)")
    }

    func testPolicyRejectsForeignHosts() {
        XCTAssertTrue(NodeCatalog.representationURLs(primary: "https://evil.example.com/v.m4s", backups: [], mode: .overseas, policy: .bilibili).isEmpty)
        XCTAssertFalse(MediaURLPolicy.bilibili.allowsURL(URL(string: "http://upos-sz-mirrorcos.bilivideo.com/v.m4s")!))
        XCTAssertFalse(MediaURLPolicy.bilibili.allowsURL(URL(string: "https://upos-sz-mirrorcos.bilivideo.com/v.txt")!))
    }

    func testCustomNodesWithPortsForTests() {
        let local = "http://127.0.0.1:9001/v.mp4?deadline=1"
        let urls = NodeCatalog.representationURLs(primary: local, backups: [],
                                                  mode: .custom([NodeAddress(host: "127.0.0.1", port: 9001), NodeAddress(host: "127.0.0.1", port: 9002)]),
                                                  policy: .any)
        XCTAssertEqual(urls, [local, "http://127.0.0.1:9002/v.mp4?deadline=1"])
        XCTAssertEqual(urls.map(NodeCatalog.nodeKey(of:)), ["127.0.0.1:9001", "127.0.0.1:9002"])
    }

    private func policyAllows(_ text: String) -> Bool {
        URL(string: text).map(MediaURLPolicy.bilibili.allowsURL) ?? false
    }

    func testPolicyAcceptsPlainHostsInAnyCase() {
        XCTAssertTrue(policyAllows("https://upos-sz-mirrorcos.bilivideo.com/v.m4s?deadline=1"))
        XCTAssertTrue(policyAllows("https://UPOS-SZ-MIRRORCOS.BILIVIDEO.COM/V.M4S"))
        XCTAssertTrue(policyAllows("https://bilivideo.com/v.mp4"))
    }

    func testPolicyRejectsLookAlikeHosts() {
        XCTAssertFalse(policyAllows("https://bilivideo.com.evil.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://evilbilivideo.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://upos-sz-mirrorcos.bilivideo.com.evil.com/v.m4s"))
    }

    func testPolicyRejectsUserinfoInBothDirections() {
        XCTAssertFalse(policyAllows("https://upos-sz-mirrorcos.bilivideo.com@evil.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://evil.com@upos-sz-mirrorcos.bilivideo.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://evil.com:pw@upos-sz-mirrorcos.bilivideo.com/v.m4s"))
    }

    func testPolicyRejectsEncodedAndBackslashHosts() {
        XCTAssertFalse(policyAllows("https://evil.com%2f.bilivideo.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://evil.com%2F.bilivideo.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://evil%2ecom.bilivideo.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://evil.com\\@upos-sz-mirrorcos.bilivideo.com/v.m4s"))
        XCTAssertFalse(policyAllows("https://evil.com\\.bilivideo.com/v.m4s"))
    }

    func testPolicyRejectsTrailingDotHost() {
        XCTAssertFalse(policyAllows("https://upos-sz-mirrorcos.bilivideo.com./v.m4s"))
    }

    func testPolicyChecksTheExtensionOnTheEncodedPath() {
        XCTAssertFalse(policyAllows("https://upos-sz-mirrorcos.bilivideo.com/v.txt%2Em4s"))
        XCTAssertFalse(policyAllows("https://upos-sz-mirrorcos.bilivideo.com/v.m4s%2F.txt"))
        XCTAssertTrue(policyAllows("https://upos-sz-mirrorcos.bilivideo.com/a%20b/v.m4s"))
    }

    func testRepresentationURLsDropEveryBypassAttempt() {
        let attempts = [
            "https://evil.com%2f.bilivideo.com/v.m4s",
            "https://evil.com\\@upos-sz-mirrorcos.bilivideo.com/v.m4s",
            "https://evil.com@upos-sz-mirrorcos.bilivideo.com/v.m4s",
        ]
        for attempt in attempts {
            XCTAssertTrue(NodeCatalog.representationURLs(primary: attempt, backups: [], mode: .overseas, policy: .bilibili).isEmpty, attempt)
        }
    }

    func testNodeKeyHasNoPortWhenThereIsNone() {
        XCTAssertEqual(NodeCatalog.nodeKey(of: primary), "upos-sz-mirrorcos.bilivideo.com")
        XCTAssertEqual(NodeCatalog.nodeKey(of: "https://UPOS-SZ-MIRRORCOS.bilivideo.com:4483/v.m4s"), "upos-sz-mirrorcos.bilivideo.com:4483")
    }

    func testEmptyCustomListFallsBackToMainland() {
        let urls = NodeCatalog.representationURLs(primary: primary, backups: [backup], mode: .custom([]), policy: .bilibili)
        XCTAssertEqual(urls, NodeCatalog.representationURLs(primary: primary, backups: [backup], mode: .mainland, policy: .bilibili))
        XCTAssertEqual(urls.count, 9)
    }
}
