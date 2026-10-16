#if DEBUG
import Foundation
import Danmaku

/// Invented danmaku for every video's seg.so, dense enough to fill the lanes: a scrolling one every 0.2 s,
/// top and bottom ones every few seconds, and now and then one from the demo account (mid 10001).
enum DanmakuFixtures {
    static let demoMid: Int64 = 10001

    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        guard url.path == "/x/v2/dm/web/seg.so" || url.path == "/x/v2/dm/wbi/web/seg.so" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let index = items.first { $0.name == "segment_index" }?.value.flatMap { Int($0) } ?? 1
        return (200, segment(index: index))
    }

    private static let phrases = [
        "前方高能", "哈哈哈哈哈", "来了来了", "这也太好看了吧", "第一次见这么用心的视频", "泪目", "打卡",
        "这里的配乐绝了", "好耶", "UP主辛苦了", "名场面", "三连了", "画质好清晰", "有人和我一样反复看吗",
        "爷青回", "太真实了", "这段可以单独剪出来", "空降成功", "awsl", "演示弹幕，不是真的",
    ]
    private static let colours: [UInt32] = [0xFE0302, 0xFFAA02, 0x00CD00, 0x89D5FF]

    /// One 6-minute segment, 1-based like the endpoint; `closed` sets state 1, the uploader's switch.
    static func segment(index: Int, closed: Bool = false) -> Data {
        let base = Int64(max(index, 1) - 1) * DanmakuSegments.lengthMs
        var reply = ProtobufWriter()
        var id: Int64 = Int64(index) * 1_000_000
        func add(_ at: Int64, mode: Int, text: String, colour: UInt32 = 0xFFFFFF, fontSize: Int = 25, midHash: String) {
            id += 1
            var elem = ProtobufWriter()
            elem.varint(1, UInt64(id))
            elem.varint(2, UInt64(base + at))
            elem.varint(3, UInt64(mode))
            elem.varint(4, UInt64(fontSize))
            elem.varint(5, UInt64(colour))
            elem.string(6, midHash)
            elem.string(7, text)
            elem.varint(8, 1_791_700_000)
            elem.varint(9, 5)
            elem.string(12, String(id))
            reply.bytes(1, elem.data)
        }
        let own = MidHash.of(uid: demoMid)
        for step in 0..<1_800 {
            let at = Int64(step) * 200 + 100
            let text = phrases[(step * 7 + index) % phrases.count]
            let colour = step % 6 == 0 ? colours[(step / 6) % colours.count] : 0xFFFFFF
            add(at, mode: 1, text: text, colour: colour, fontSize: step % 9 == 4 ? 18 : 25,
                midHash: String(UInt32(truncatingIfNeeded: step &* 2_654_435_761), radix: 16))
        }
        for step in 0..<144 {
            add(Int64(step) * 2_500 + 300, mode: 5, text: "顶部弹幕 \(step + 1)", colour: 0xFFD302, midHash: "5eed\(step)")
        }
        for step in 0..<103 {
            add(Int64(step) * 3_500 + 900, mode: 4, text: "底部弹幕：第\(step + 1)句", midHash: "b077\(step)")
        }
        for step in 0..<36 {
            add(Int64(step) * 10_000 + 4_000, mode: 1, text: "我发的弹幕", midHash: own)
        }
        if closed { reply.varint(2, 1) }
        return reply.data
    }

    /// Writes just the protobuf the danmaku reader needs, for the fixtures.
    struct ProtobufWriter {
        private(set) var data = Data()

        mutating func varint(_ field: Int, _ value: UInt64) {
            raw(UInt64(field << 3))
            raw(value)
        }

        mutating func bytes(_ field: Int, _ value: Data) {
            raw(UInt64(field << 3 | 2))
            raw(UInt64(value.count))
            data.append(value)
        }

        mutating func string(_ field: Int, _ value: String) {
            bytes(field, Data(value.utf8))
        }

        private mutating func raw(_ value: UInt64) {
            var rest = value
            while rest >= 0x80 {
                data.append(UInt8(rest & 0x7F) | 0x80)
                rest >>= 7
            }
            data.append(UInt8(rest))
        }
    }
}
#endif
