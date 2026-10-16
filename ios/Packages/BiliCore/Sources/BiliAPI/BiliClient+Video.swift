import Foundation

private struct OnlineTotal: Decodable {
    let total: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        total = try container.first(String.self, "total") ?? ""
    }
}

/// Ads and game cards in the related list carry a `redirect_url` instead of a playable video.
private struct RelatedItem: Decodable {
    let card: VideoCard?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let redirect = try container.first(String.self, "redirect_url") ?? ""
        if redirect.isEmpty {
            card = try? VideoCard(from: decoder)
        } else {
            card = nil
        }
    }
}

extension BiliClient {
    public func videoDetail(bvid: String) async throws -> VideoDetail {
        try await get("/x/web-interface/wbi/view", query: ["bvid": bvid], signed: true)
    }

    public func playerInfo(bvid: String, cid: Int64) async throws -> PlayerInfo {
        try await get("/x/player/wbi/v2", query: ["bvid": bvid, "cid": String(cid)], signed: true)
    }

    /// The server's display string ("1.2万+"), not a number.
    public func onlineCount(aid: Int64, bvid: String, cid: Int64) async throws -> String {
        let online: OnlineTotal = try await get("/x/player/online/total",
                                                query: ["aid": String(aid), "bvid": bvid, "cid": String(cid)], signed: false)
        return online.total
    }

    public func related(bvid: String) async throws -> [VideoCard] {
        let items: [Lossy<RelatedItem>] = try await get("/x/web-interface/archive/related", query: ["bvid": bvid], signed: false)
        return items.compactMap { $0.value?.card }
    }

    public func heartbeat(bvid: String, cid: Int64, playedTime: Int) async throws {
        try await post("/x/click-interface/web/heartbeat",
                       form: ["bvid": bvid, "cid": String(cid), "type": "3", "played_time": String(playedTime)],
                       referer: "https://www.bilibili.com/video/\(bvid)")
    }

    public func addToWatchLater(aid: Int64) async throws {
        try await post("/x/v2/history/toview/add", form: ["aid": String(aid)])
    }
}
