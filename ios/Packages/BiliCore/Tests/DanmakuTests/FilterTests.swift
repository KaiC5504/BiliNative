import XCTest
@testable import Danmaku

func makeElem(_ content: String = "弹幕", at progress: Int64 = 0, mode: Int = 1, color: UInt32 = 0xFFFFFF,
              midHash: String = "", colorful: Int = 0) -> DanmakuElem {
    DanmakuElem(progressMs: progress, mode: mode, color: color, midHash: midHash, content: content, colorful: colorful)
}

final class FilterTests: XCTestCase {
    private func shown(_ elems: [DanmakuElem], _ options: DanmakuFilterOptions = .init(), rules: [BlockRule] = [],
                       own: String? = nil) -> [String] {
        DanmakuFilter.apply(elems, options: options, rules: rules, ownHash: own).map(\.text)
    }

    func testMidHashMatchesCRC32() {
        XCTAssertEqual(MidHash.of(uid: 12345), "cbf53a1c")   // zlib.crc32(b"12345")
        XCTAssertEqual(MidHash.of(uid: 7), "6abf4a82")
    }

    func testMidHashHasNoLeadingZeros() {
        for uid in Int64(0)..<2_000 {
            let hash = MidHash.of(uid: uid)
            XCTAssertFalse(hash.hasPrefix("0"), "uid \(uid) gave \(hash)")
        }
    }

    func testModesSevenEightNineAreAlwaysDropped() {
        let elems = (1...9).map { makeElem("m\($0)", at: Int64($0), mode: $0) }
        XCTAssertEqual(shown(elems), ["m1", "m2", "m3", "m4", "m5", "m6"])
    }

    func testTypeAndColourBlocks() {
        let elems = [
            makeElem("scroll", at: 1, mode: 1),
            makeElem("reverse", at: 2, mode: 6),
            makeElem("bottom", at: 3, mode: 4),
            makeElem("top", at: 4, mode: 5),
            makeElem("red", at: 5, mode: 1, color: 0xFF0000),
            makeElem("gradient", at: 6, mode: 1, colorful: 60001),
        ]
        XCTAssertEqual(shown(elems), ["scroll", "reverse", "bottom", "top", "red", "gradient"])
        XCTAssertEqual(shown(elems, .init(blockScroll: true)), ["bottom", "top"])
        XCTAssertEqual(shown(elems, .init(blockFixed: true)), ["scroll", "reverse", "red", "gradient"])
        XCTAssertEqual(shown(elems, .init(hideBottom: true)), ["scroll", "reverse", "top", "red", "gradient"])
        XCTAssertEqual(shown(elems, .init(blockColored: true)), ["scroll", "reverse", "bottom", "top"])
        XCTAssertEqual(shown(elems, .init(blockAdvanced: true)), ["scroll", "reverse", "bottom", "top", "red", "gradient"])
    }

    func testRulesKeywordRegexUserAndOwnExempt() {
        let elems = [
            makeElem("剧透警告", at: 1),
            makeElem("Spoiler ahead", at: 2),
            makeElem("路人甲", at: 3, midHash: "deadbeef"),
            makeElem("普通弹幕", at: 4, midHash: "11111111"),
            makeElem("我也剧透", at: 5, midHash: "aaaa0001"),
        ]
        let rules = [
            BlockRule(id: 1, kind: .keyword, filter: "剧透"),
            BlockRule(id: 2, kind: .regex, filter: "/spoil.*/"),
            BlockRule(id: 3, kind: .user, filter: "deadbeef"),
            BlockRule(id: 4, kind: .regex, filter: "([unclosed"),
        ]
        XCTAssertEqual(shown(elems, rules: rules), ["普通弹幕"])
        XCTAssertEqual(shown(elems, rules: rules, own: "aaaa0001"), ["普通弹幕", "我也剧透"])
        XCTAssertEqual(shown(elems, .init(applyRules: false), rules: rules).count, 5)
        let result = DanmakuFilter.apply(elems, options: .init(), rules: rules, ownHash: "aaaa0001")
        XCTAssertEqual(result.map(\.isOwn), [false, true])
    }

    func testRegexWithoutSlashesAndEmptyRulesAreHandled() {
        let elems = [makeElem("abc", at: 1), makeElem("xyz", at: 2)]
        let rules = [BlockRule(id: 1, kind: .regex, filter: "^A"), BlockRule(id: 2, kind: .keyword, filter: "")]
        XCTAssertEqual(shown(elems, rules: rules), ["xyz"])
    }

    func testEmptyRegexBlocksNothing() {
        let elems = [makeElem("abc", at: 1), makeElem("xyz", at: 2)]
        XCTAssertEqual(shown(elems, rules: [BlockRule(id: 1, kind: .regex, filter: "//")]), ["abc", "xyz"])
    }

    func testDedupeMergesWithinTenSecondsAndCountBlockDropsMerged() {
        let elems = [makeElem("哈哈", at: 1_000), makeElem("哈哈", at: 5_000), makeElem("哈哈", at: 12_000)]
        XCTAssertEqual(shown(elems, .init(dedupe: true)), ["哈哈 ×2", "哈哈"])
        XCTAssertEqual(shown(elems, .init(blockCount: true, dedupe: true)), ["哈哈"])
        XCTAssertEqual(shown(elems, .init(blockCount: true)), ["哈哈"])
        XCTAssertEqual(shown(elems), ["哈哈", "哈哈", "哈哈"])
    }

    func testDedupeKeepsTheFirstOnesTimeAndCountsAll() {
        let elems = [makeElem("666", at: 2_000), makeElem("666", at: 4_000), makeElem("666", at: 9_000), makeElem("别的", at: 3_000)]
        let result = DanmakuFilter.apply(elems, options: .init(dedupe: true), rules: [], ownHash: nil)
        XCTAssertEqual(result.map(\.text), ["666 ×3", "别的"])
        XCTAssertEqual(result.map(\.elem.progressMs), [2_000, 3_000])
    }

    func testUnsortedInputComesOutSortedAndMergesRegardless() {
        let elems = [makeElem("b", at: 3_000), makeElem("a", at: 1_000), makeElem("a", at: 2_000)]
        let result = DanmakuFilter.apply(elems, options: .init(dedupe: true), rules: [], ownHash: nil)
        XCTAssertEqual(result.map(\.text), ["a ×2", "b"])
    }

    func testOwnDanmakuIsNeverMergedAway() {
        let elems = [makeElem("哈哈", at: 1_000, midHash: "other"), makeElem("哈哈", at: 2_000, midHash: "mine")]
        let result = DanmakuFilter.apply(elems, options: .init(blockCount: true, dedupe: true), rules: [], ownHash: "mine")
        XCTAssertEqual(result.map(\.text), ["哈哈", "哈哈"])
        XCTAssertEqual(result.map(\.isOwn), [false, true])
    }

    func testOptionsDecodeFromOlderSettingsWithMissingKeys() throws {
        let decoded = try JSONDecoder().decode(DanmakuFilterOptions.self, from: Data(#"{"dedupe":true}"#.utf8))
        XCTAssertEqual(decoded, DanmakuFilterOptions(dedupe: true))
        XCTAssertTrue(decoded.applyRules)
        let round = try JSONDecoder().decode(DanmakuFilterOptions.self, from: JSONEncoder().encode(DanmakuFilterOptions(blockFixed: true, applyRules: false)))
        XCTAssertEqual(round, DanmakuFilterOptions(blockFixed: true, applyRules: false))
    }
}
