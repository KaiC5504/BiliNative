import XCTest
import BiliShared
@testable import Ripper

final class HurryPlacementTests: XCTestCase {
    let piece: Int64 = 64 * 1024

    func url(_ host: String, _ query: String = "os=cosovbv") -> String { "https://\(host)/upgcxcode/1/2/3/v.m4s?\(query)" }

    /// One finished transfer: the node is known, with `load` 1, so its expected time holds up to four in flight.
    func measure(_ stats: NodeStats, _ url: String, ttfbMs: Double, bytesPerSecond: Double) {
        stats.begin(url)
        stats.firstByte(url, ms: ttfbMs)
        stats.body(url, bytes: 1_000_000, ms: 1_000_000 / bytesPerSecond * 1000)
        stats.end(url, receiving: true)
    }

    func counts(_ primaries: [String]) -> [String: Int] {
        primaries.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    func testNoNodeKnownSpreadsByInflight() {
        let urls = [url("a.example"), url("b.example"), url("c.example")]
        let primaries = HurryPlacement.assign(urls: urls, count: 6, pieceBytes: piece, nodes: NodeStats(), delivered: { _ in true })
        XCTAssertEqual(primaries, urls + urls)
    }

    func testUnknownNodesTakeAShareAtTwiceTheBestCost() {
        let stats = NodeStats()
        let known = url("known.example")
        measure(stats, known, ttfbMs: 20, bytesPerSecond: 10_000_000)
        let urls = [known, url("u1.example"), url("u2.example")]
        let result = counts(HurryPlacement.assign(urls: urls, count: 8, pieceBytes: piece, nodes: stats, delivered: { _ in true }))
        for url in urls { XCTAssertGreaterThanOrEqual(result[url] ?? 0, 1, "\(result)") }
        XCTAssertGreaterThan(result[known] ?? 0, result[urls[1]] ?? 0)
        XCTAssertGreaterThan(result[known] ?? 0, result[urls[2]] ?? 0)
    }

    func testNoNodeTakesMoreThanHalfWithThreeHosts() {
        let stats = NodeStats()
        let fast = url("fast.example"), slowOne = url("slow1.example"), slowTwo = url("slow2.example")
        measure(stats, fast, ttfbMs: 10, bytesPerSecond: 100_000_000)
        measure(stats, slowOne, ttfbMs: 10, bytesPerSecond: 1_000_000)
        measure(stats, slowTwo, ttfbMs: 10, bytesPerSecond: 1_000_000)
        // Fast costs about 11 ms however full it gets, a slow node 75.5 ms up to four in flight. Virtual
        // counts (fast, slow1, slow2), carried = their sum; fast pays 1e5 when it has ≥ 2 and more than half:
        //  1: (0,0,0) fast           2: (1,0,0) fast
        //  3: (2,0,0) 4 > 2, slows tie with none in flight → slow1
        //  4: (2,1,0) 4 > 3, slows tie at 75.5 → slow2, carrying less
        //  5: (2,1,1) 4 = 4 → fast   6: (3,1,1) 6 > 5 → slow1
        //  7: (3,2,1) 6 = 6 → fast   8: (4,2,1) 8 > 7 → slow2, carrying less
        //  9: (4,2,2) 8 = 8 → fast  10: (5,2,2) 10 > 9 → slow1
        let primaries = HurryPlacement.assign(urls: [fast, slowOne, slowTwo], count: 10, pieceBytes: piece, nodes: stats, delivered: { _ in true })
        XCTAssertEqual(primaries, [fast, fast, slowOne, slowTwo, fast, slowOne, fast, slowTwo, fast, slowOne])
        XCTAssertEqual(counts(primaries), [fast: 5, slowOne: 3, slowTwo: 2])
    }

    /// Review focus 1: an Akamai-only account has one host; the half-share rule must not push pieces nowhere.
    func testASingleHostTakesEveryPiece() {
        let stats = NodeStats()
        let akamai = url("upos-hz-mirrorakam.akamaized.net", "os=akam")
        measure(stats, akamai, ttfbMs: 30, bytesPerSecond: 20_000_000)
        let primaries = HurryPlacement.assign(urls: [akamai], count: 5, pieceBytes: piece, nodes: stats, delivered: { _ in true })
        XCTAssertEqual(primaries, Array(repeating: akamai, count: 5))
    }

    func testFullNodesAndUndeliveredAddressesGoLast() {
        let stats = NodeStats()
        let full = url("full.example"), open = url("open.example")
        measure(stats, full, ttfbMs: 5, bytesPerSecond: 100_000_000)
        measure(stats, open, ttfbMs: 50, bytesPerSecond: 1_000_000)
        // Silent while receiving: capped at the one transfer it carries.
        stats.begin(full); stats.firstByte(full, ms: 5); stats.silent(full, waitedMs: 5_500)
        XCTAssertTrue(stats.isFull(full))
        let primaries = HurryPlacement.assign(urls: [full, open], count: 6, pieceBytes: piece, nodes: stats, delivered: { _ in true })
        XCTAssertEqual(primaries, Array(repeating: open, count: 6))

        // Capped at two but idle: the pieces placed on it count toward the cap.
        let capped = url("capped.example")
        measure(stats, capped, ttfbMs: 5, bytesPerSecond: 100_000_000)
        stats.begin(capped); stats.begin(capped); stats.firstByte(capped, ms: 5); stats.firstByte(capped, ms: 5)
        stats.silent(capped, waitedMs: 5_500)
        stats.end(capped, receiving: true); stats.end(capped, receiving: true)
        XCTAssertFalse(stats.isFull(capped))
        let spilled = HurryPlacement.assign(urls: [capped, open], count: 5, pieceBytes: piece, nodes: stats, delivered: { _ in true })
        XCTAssertEqual(counts(spilled), [capped: 2, open: 3])

        // Two addresses of one node cost the same; the one that has delivered goes first.
        let refused = url("akam.example", "os=cosovbv"), served = url("akam.example", "os=akam")
        let first = HurryPlacement.assign(urls: [refused, served], count: 3, pieceBytes: piece, nodes: NodeStats(), delivered: { $0 == served })
        XCTAssertEqual(first, [served, served, served])
    }
}
