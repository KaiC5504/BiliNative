public enum InitFixResult: Equatable, Sendable {
    case unchanged
    case rewritten([UInt8])
    case unplayable(String)
}

/// AVPlayer only plays HEVC from HLS when the sample entry is `hvc1` (parameter sets out of band).
/// Bilibili often labels HEVC `hev1`. When the `hvcC` box already carries VPS, SPS and PPS, the
/// two labels describe the same bytes, so renaming the four-character code is enough.
public enum InitSegmentFixer {
    public static func fixHEV1(_ bytes: [UInt8]) -> InitFixResult {
        var output = bytes
        var rewrote = false
        let topLevel = BoxReader.boxes(in: bytes, from: 0, to: bytes.count)
        let moovs = topLevel.filter { $0.type == "moov" }
        // Boxes cut off by the end of the buffer are dropped by BoxReader, so a missing moov after an
        // ftyp means the caller's buffer is short, and an unpatched hev1 could be hiding in the rest.
        if moovs.isEmpty, startsWithFtyp(bytes) { return .unplayable("incomplete moov") }
        for moov in moovs {
            let (entries, hasBrokenHev1) = sampleEntries(bytes, moov)
            if hasBrokenHev1 { return .unplayable("hev1 sample entry is truncated or malformed") }
            for entry in entries where entry.type == "hev1" {
                guard hasParameterSets(bytes, entry) else { return .unplayable("hev1 without VPS/SPS/PPS in hvcC") }
                output.replaceSubrange((entry.start + 4)..<(entry.start + 8), with: Array("hvc1".utf8))
                rewrote = true
            }
        }
        return rewrote ? .rewritten(output) : .unchanged
    }

    /// The type of the first sample entry in the first moov, or nil when there is none.
    public static func sampleEntry(_ bytes: [UInt8]) -> String? {
        guard let moov = BoxReader.boxes(in: bytes, from: 0, to: bytes.count).first(where: { $0.type == "moov" }) else { return nil }
        return sampleEntries(bytes, moov).entries.first?.type
    }

    private static func startsWithFtyp(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 8 && BoxReader.type(bytes, 4) == "ftyp"
    }

    private static func children(_ bytes: [UInt8], _ box: BoxHeader, type: String) -> [BoxHeader] {
        BoxReader.boxes(in: bytes, from: box.payloadStart, to: box.end).filter { $0.type == type }
    }

    private static func sampleEntries(_ bytes: [UInt8], _ moov: BoxHeader) -> (entries: [BoxHeader], hasBrokenHev1: Bool) {
        var entries: [BoxHeader] = []
        var hasBrokenHev1 = false
        for trak in children(bytes, moov, type: "trak") {
            for mdia in children(bytes, trak, type: "mdia") {
                for minf in children(bytes, mdia, type: "minf") {
                    for stbl in children(bytes, minf, type: "stbl") {
                        for stsd in children(bytes, stbl, type: "stsd") {
                            // stsd is a full box: version/flags and entry_count come first.
                            let entriesStart = stsd.payloadStart + 8
                            let found = BoxReader.boxes(in: bytes, from: entriesStart, to: stsd.end)
                            entries += found
                            // BoxReader stops at an entry whose size runs past stsd; its type is still readable.
                            let rest = found.last?.end ?? entriesStart
                            if rest + 8 <= stsd.end, BoxReader.type(bytes, rest + 4) == "hev1" { hasBrokenHev1 = true }
                        }
                    }
                }
            }
        }
        return (entries, hasBrokenHev1)
    }

    private static func hasParameterSets(_ bytes: [UInt8], _ entry: BoxHeader) -> Bool {
        // A VisualSampleEntry has 78 bytes of fixed fields before its child boxes.
        let childStart = entry.payloadStart + 78
        guard childStart <= entry.end,
              let hvcC = BoxReader.boxes(in: bytes, from: childStart, to: entry.end).first(where: { $0.type == "hvcC" }) else {
            return false
        }
        var cursor = hvcC.payloadStart + 22
        guard cursor < hvcC.end else { return false }
        let arrayCount = Int(bytes[cursor])
        cursor += 1
        var found = Set<UInt8>()
        for _ in 0..<arrayCount {
            guard cursor + 3 <= hvcC.end else { return false }
            let nalType = bytes[cursor] & 0x3f
            let nalCount = Int(BoxReader.uint16(bytes, cursor + 1))
            cursor += 3
            for _ in 0..<nalCount {
                guard cursor + 2 <= hvcC.end else { return false }
                cursor += 2 + Int(BoxReader.uint16(bytes, cursor))
                guard cursor <= hvcC.end else { return false }
            }
            if nalCount > 0 { found.insert(nalType) }
        }
        // 32 = VPS, 33 = SPS, 34 = PPS.
        return found.isSuperset(of: [32, 33, 34])
    }
}
