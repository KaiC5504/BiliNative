import XCTest
@testable import DashHLS

final class InitSegmentFixerTests: XCTestCase {
    func testRewritesHev1WithParameterSets() throws {
        let original = MP4Builder.initSegment(entryType: "hev1", nalTypes: [32, 33, 34]) + MP4Builder.box("sidx", [1, 2, 3])
        guard case .rewritten(let fixed) = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected a rewrite") }
        XCTAssertEqual(fixed.count, original.count)
        let position = try XCTUnwrap(indexOf("hev1", in: original))
        XCTAssertEqual(Array(fixed[position..<position + 4]), Array("hvc1".utf8))
        var restored = fixed
        restored.replaceSubrange(position..<position + 4, with: Array("hev1".utf8))
        XCTAssertEqual(restored, original)
    }

    func testRefusesHev1WithoutPPS() {
        guard case .unplayable = InitSegmentFixer.fixHEV1(MP4Builder.initSegment(entryType: "hev1", nalTypes: [32, 33])) else {
            return XCTFail("expected unplayable")
        }
    }

    func testLeavesOtherEntriesAlone() {
        XCTAssertEqual(InitSegmentFixer.fixHEV1(MP4Builder.initSegment(entryType: "hvc1", nalTypes: [32, 33, 34])), .unchanged)
        XCTAssertEqual(InitSegmentFixer.fixHEV1(MP4Builder.initSegment(entryType: "avc1", nalTypes: [])), .unchanged)
        XCTAssertEqual(InitSegmentFixer.fixHEV1([0, 1, 2]), .unchanged)
    }

    func testRefusesHev1WithoutHvcCBox() {
        let original = initSegment(entryChildren: [])
        guard case .unplayable = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected unplayable") }
    }

    func testRefusesHev1WhoseParameterSetArraysAreEmpty() {
        // The array header names VPS, SPS and PPS but each holds zero NAL units.
        let payload = [UInt8](repeating: 0, count: 22) + [3] + [32, 0, 0, 33, 0, 0, 34, 0, 0]
        let original = initSegment(entryChildren: MP4Builder.box("hvcC", payload))
        guard case .unplayable = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected unplayable") }
    }

    func testRefusesHev1WhoseHvcCIsTruncatedInsideANalUnit() {
        // Box sizes are consistent, but the last NAL unit claims more bytes than the hvcC holds.
        let payload = [UInt8](repeating: 0, count: 22) + [3]
            + [32] + MP4Builder.be16(1) + MP4Builder.be16(2) + [0xAA, 0xBB]
            + [33] + MP4Builder.be16(1) + MP4Builder.be16(2) + [0xAA, 0xBB]
            + [34] + MP4Builder.be16(1) + MP4Builder.be16(500) + [0xAA, 0xBB]
        let original = initSegment(entryChildren: MP4Builder.box("hvcC", payload))
        guard case .unplayable = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected unplayable") }
    }

    func testRefusesHev1WhoseHvcCEndsBeforeTheArrays() {
        for payloadSize in [0, 10, 22, 23, 24] {
            let original = initSegment(entryChildren: MP4Builder.box("hvcC", [UInt8](repeating: 0, count: payloadSize)))
            guard case .unplayable = InitSegmentFixer.fixHEV1(original) else {
                return XCTFail("expected unplayable for a \(payloadSize) byte hvcC")
            }
        }
    }

    func testRefusesHev1ShorterThanItsFixedFields() {
        let entry = MP4Builder.box("hev1", [UInt8](repeating: 0, count: 40))
        guard case .unplayable = InitSegmentFixer.fixHEV1(initSegment(entry: entry)) else { return XCTFail("expected unplayable") }
    }

    func testRewritesEveryHev1EntryAndOnlyThose() throws {
        let hev1 = MP4Builder.box("hev1", [UInt8](repeating: 0, count: 78) + MP4Builder.hvcC(nalTypes: [32, 33, 34]))
        let avc1 = MP4Builder.box("avc1", [UInt8](repeating: 0, count: 78))
        let original = initSegment(entries: [hev1, avc1, hev1])
        guard case .rewritten(let fixed) = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected a rewrite") }
        XCTAssertEqual(fixed.count, original.count)
        XCTAssertNil(indexOf("hev1", in: fixed))
        XCTAssertEqual(occurrences("hvc1", in: fixed), 2)
        XCTAssertEqual(occurrences("avc1", in: fixed), 1)
    }

    func testUnplayableEntryWinsOverRewritableOne() {
        let good = MP4Builder.box("hev1", [UInt8](repeating: 0, count: 78) + MP4Builder.hvcC(nalTypes: [32, 33, 34]))
        let bad = MP4Builder.box("hev1", [UInt8](repeating: 0, count: 78) + MP4Builder.hvcC(nalTypes: [33]))
        guard case .unplayable = InitSegmentFixer.fixHEV1(initSegment(entries: [good, bad])) else { return XCTFail("expected unplayable") }
    }

    func testBoxSizesPastTheBufferNeverTrap() throws {
        let valid = MP4Builder.initSegment(entryType: "hev1", nalTypes: [32, 33, 34])
        for length in 0..<valid.count {
            _ = InitSegmentFixer.fixHEV1(Array(valid[0..<length]))
        }
        let sizeOffsets = [
            try XCTUnwrap(boxStart("moov", in: valid)),
            try XCTUnwrap(boxStart("hev1", in: valid)),
            try XCTUnwrap(boxStart("hvcC", in: valid)),
        ]
        for offset in sizeOffsets {
            var hostile = valid
            hostile.replaceSubrange(offset..<offset + 4, with: [0xFF, 0xFF, 0xFF, 0xFF])
            _ = InitSegmentFixer.fixHEV1(hostile)
        }
        var largeSize = valid
        largeSize.replaceSubrange(sizeOffsets[0]..<sizeOffsets[0] + 4, with: MP4Builder.be32(1))
        _ = InitSegmentFixer.fixHEV1(largeSize)
    }

    func testOversizedHev1EntryIsUnplayable() throws {
        var original = MP4Builder.initSegment(entryType: "hev1", nalTypes: [32, 33, 34])
        let position = try XCTUnwrap(boxStart("hev1", in: original))
        original.replaceSubrange(position..<position + 4, with: MP4Builder.be32(0x7FFF_FFFF))
        guard case .unplayable = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected unplayable") }
    }

    func testOversizedNonHevcEntryIsLeftAlone() throws {
        var original = MP4Builder.initSegment(entryType: "avc1", nalTypes: [])
        let position = try XCTUnwrap(boxStart("avc1", in: original))
        original.replaceSubrange(position..<position + 4, with: MP4Builder.be32(0x7FFF_FFFF))
        XCTAssertEqual(InitSegmentFixer.fixHEV1(original), .unchanged)
    }

    func testBufferCutBeforeMoovEndsIsUnplayableAtEveryLength() {
        let valid = MP4Builder.initSegment(entryType: "hev1", nalTypes: [32, 33, 34])
        for length in 8..<valid.count {
            guard case .unplayable = InitSegmentFixer.fixHEV1(Array(valid[0..<length])) else {
                return XCTFail("expected unplayable at \(length) bytes")
            }
        }
        guard case .rewritten = InitSegmentFixer.fixHEV1(valid) else { return XCTFail("expected a rewrite") }
    }

    func testBuffersWithoutFtypOrMoovAreLeftAlone() {
        XCTAssertEqual(InitSegmentFixer.fixHEV1([]), .unchanged)
        XCTAssertEqual(InitSegmentFixer.fixHEV1(MP4Builder.box("free", [1, 2, 3])), .unchanged)
    }

    func testFtypWithoutMoovIsUnplayable() {
        guard case .unplayable(let reason) = InitSegmentFixer.fixHEV1(MP4Builder.box("ftyp", Array("iso6".utf8) + MP4Builder.be32(0))) else {
            return XCTFail("expected unplayable")
        }
        XCTAssertEqual(reason, "incomplete moov")
    }

    func testRewritesAnFfmpegHev1InitSegment() throws {
        let original = RealHEV1InitSegment.bytes
        XCTAssertEqual(original.count, 3195)
        guard case .rewritten(let fixed) = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected a rewrite") }
        XCTAssertEqual(fixed.count, original.count)
        let changed = original.indices.filter { original[$0] != fixed[$0] }
        // hev1 -> hvc1 changes only the second and third letters.
        let position = try XCTUnwrap(indexOf("hev1", in: original))
        XCTAssertEqual(changed, [position + 1, position + 2])
        XCTAssertEqual(Array(fixed[position..<position + 4]), Array("hvc1".utf8))
    }

    private func initSegment(entryChildren: [UInt8]) -> [UInt8] {
        initSegment(entry: MP4Builder.box("hev1", [UInt8](repeating: 0, count: 78) + entryChildren))
    }

    private func initSegment(entry: [UInt8]) -> [UInt8] { initSegment(entries: [entry]) }

    private func initSegment(entries: [[UInt8]]) -> [UInt8] {
        let stsd = MP4Builder.box("stsd", [0, 0, 0, 0] + MP4Builder.be32(UInt32(entries.count)) + entries.flatMap { $0 })
        let trak = MP4Builder.box("trak", MP4Builder.box("mdia", MP4Builder.box("minf", MP4Builder.box("stbl", stsd))))
        return MP4Builder.box("ftyp", Array("iso6".utf8) + MP4Builder.be32(0)) + MP4Builder.box("moov", trak)
    }

    private func indexOf(_ text: String, in bytes: [UInt8]) -> Int? {
        let needle = Array(text.utf8)
        guard bytes.count >= needle.count else { return nil }
        return (0...(bytes.count - needle.count)).first { Array(bytes[$0..<$0 + needle.count]) == needle }
    }

    private func boxStart(_ type: String, in bytes: [UInt8]) -> Int? {
        indexOf(type, in: bytes).map { $0 - 4 }
    }

    private func occurrences(_ text: String, in bytes: [UInt8]) -> Int {
        let needle = Array(text.utf8)
        guard bytes.count >= needle.count else { return 0 }
        return (0...(bytes.count - needle.count)).filter { Array(bytes[$0..<$0 + needle.count]) == needle }.count
    }
}
