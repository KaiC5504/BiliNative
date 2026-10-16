import Foundation
import Danmaku

public struct DanmakuDraft: Sendable {
    public var cid: Int64
    public var bvid: String
    public var text: String
    public var mode: Int
    public var fontSize: Int
    public var color: UInt32
    /// The 大会员 gradient colour; the server refuses it for other accounts.
    public var gradient: Bool
    public var progressMs: Int64

    public init(cid: Int64, bvid: String, text: String, mode: Int, fontSize: Int, color: UInt32, gradient: Bool, progressMs: Int64) {
        self.cid = cid
        self.bvid = bvid
        self.text = text
        self.mode = mode
        self.fontSize = fontSize
        self.color = color
        self.gradient = gradient
        self.progressMs = progressMs
    }
}

private struct BlockRuleList: Decodable {
    let rule: [Lossy<BlockRuleItem>]?
}

private struct BlockRuleItem: Decodable {
    let id: Int64
    let type: Int?
    let filter: String?

    var rule: BlockRule? {
        guard let type, let kind = BlockRule.Kind(rawValue: type), let filter else { return nil }
        return BlockRule(id: id, kind: kind, filter: filter)
    }
}

private struct PostedDanmaku: Decodable {
    let dmid: Int64?
}

extension BiliClient {
    /// One 6-minute slice of a video's danmaku, `index` counting from 1.
    public func danmakuSegment(cid: Int64, index: Int) async throws -> DanmakuSegment {
        let query = ["type": "1", "oid": String(cid), "segment_index": String(index)]
        let data: Data
        do {
            data = try await getData("/x/v2/dm/web/seg.so", query: query, signed: false)
        } catch BiliError.http(let status) where status == 403 || status == 412 {
            // Risk control sometimes refuses the plain endpoint while the signed twin still answers.
            data = try await getData("/x/v2/dm/wbi/web/seg.so", query: query, signed: true)
        }
        do {
            return try DanmakuSegment.decode(data)
        } catch {
            throw BiliError.decoding("danmaku segment \(index): \(error)")
        }
    }

    public func danmakuBlockRules() async throws -> [BlockRule] {
        let list: BlockRuleList = try await get("/x/dm/filter/user", query: [:], signed: false)
        return (list.rule ?? []).compactMap { $0.value?.rule }
    }

    public func addBlockRule(_ kind: BlockRule.Kind, filter: String) async throws -> BlockRule {
        let added: BlockRuleItem = try await post("/x/dm/filter/user/add",
                                                  form: ["type": String(kind.rawValue), "filter": filter])
        return added.rule ?? BlockRule(id: added.id, kind: kind, filter: filter)
    }

    public func deleteBlockRule(id: Int64) async throws {
        try await post("/x/dm/filter/user/del", form: ["ids": String(id)])
    }

    /// Returns the new danmaku's id, or 0 when the server accepted it without one.
    public func postDanmaku(_ draft: DanmakuDraft) async throws -> Int64 {
        var form = [
            "type": "1",
            "oid": String(draft.cid),
            "bvid": draft.bvid,
            "msg": draft.text,
            "mode": String(draft.mode),
            "fontsize": String(draft.fontSize),
            "color": String(draft.color),
            "progress": String(draft.progressMs),
            "rnd": String(Int64((now().timeIntervalSince1970 * 1_000_000).rounded())),
            "pool": "0",
        ]
        if draft.gradient { form["colorful"] = "60001" }
        let posted: PostedDanmaku = try await post("/x/v2/dm/post", form: form,
                                                   referer: "https://www.bilibili.com/video/\(draft.bvid)")
        return posted.dmid ?? 0
    }
}
