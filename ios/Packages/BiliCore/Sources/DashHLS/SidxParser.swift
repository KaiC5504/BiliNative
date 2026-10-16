import BiliShared

public enum SidxParser {
    /// Segments from the first `sidx` box in `bytes`, which begins at file offset `absoluteStart`.
    public static func parse(_ bytes: [UInt8], absoluteStart: Int64) -> [MediaSegment]? {
        guard let box = BoxReader.boxes(in: bytes, from: 0, to: bytes.count).first(where: { $0.type == "sidx" }) else { return nil }
        var cursor = box.payloadStart
        guard cursor + 12 <= box.end else { return nil }
        let version = bytes[cursor]
        cursor += 8
        let timescale = Double(BoxReader.uint32(bytes, cursor))
        cursor += 4
        guard timescale > 0 else { return nil }

        let earliest: UInt64
        let firstOffset: UInt64
        if version == 0 {
            guard cursor + 8 <= box.end else { return nil }
            earliest = UInt64(BoxReader.uint32(bytes, cursor))
            firstOffset = UInt64(BoxReader.uint32(bytes, cursor + 4))
            cursor += 8
        } else if version == 1 {
            guard cursor + 16 <= box.end else { return nil }
            earliest = BoxReader.uint64(bytes, cursor)
            firstOffset = BoxReader.uint64(bytes, cursor + 8)
            cursor += 16
        } else {
            return nil
        }
        cursor += 2
        guard cursor + 2 <= box.end else { return nil }
        let count = Int(BoxReader.uint16(bytes, cursor))
        cursor += 2
        guard count >= 1, count <= 10_000, cursor + count * 12 <= box.end else { return nil }

        // Version 1 offsets are 64-bit; anything beyond Int64 is hostile, and so is a sum that overflows.
        guard firstOffset <= UInt64(Int64.max) else { return nil }
        let (afterBox, boxOverflow) = absoluteStart.addingReportingOverflow(Int64(box.end))
        let (firstByte, offsetOverflow) = afterBox.addingReportingOverflow(Int64(firstOffset))
        guard !boxOverflow, !offsetOverflow else { return nil }
        var byteCursor = firstByte
        var time = Double(earliest)
        var segments: [MediaSegment] = []
        for _ in 0..<count {
            let reference = BoxReader.uint32(bytes, cursor)
            let size = Int64(reference & 0x7fff_ffff)
            let duration = Double(BoxReader.uint32(bytes, cursor + 4))
            cursor += 12
            let (next, overflow) = byteCursor.addingReportingOverflow(size)
            guard size > 0, !overflow, let range = ByteRange(start: byteCursor, end: next - 1) else { return nil }
            // Type 1 points at another sidx; dropping it would leave byte and time gaps, so the caller falls back to direct mode.
            guard reference >> 31 == 0 else { return nil }
            segments.append(MediaSegment(index: segments.count, range: range, startTime: time / timescale, duration: duration / timescale))
            byteCursor = next
            time += duration
        }
        return segments.isEmpty ? nil : segments
    }
}
