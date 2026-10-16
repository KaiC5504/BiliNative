import Foundation
import Danmaku

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
}
