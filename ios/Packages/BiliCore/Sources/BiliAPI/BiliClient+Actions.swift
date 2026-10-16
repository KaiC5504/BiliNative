import Foundation

private struct FolderList: Decodable {
    let folders: [FavFolder]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let list = try container.first([Lossy<FavFolder>].self, "list") ?? []
        folders = list.compactMap(\.value)
    }
}

private struct CoinBalance: Decodable {
    let money: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        money = try container.first(Double.self, "money") ?? 0
    }
}

private func videoReferer(_ bvid: String) -> String {
    "https://www.bilibili.com/video/\(bvid)"
}

extension BiliClient {
    public func relation(aid: Int64, bvid: String) async throws -> VideoRelation {
        try await get("/x/web-interface/archive/relation", query: ["aid": String(aid), "bvid": bvid], signed: false)
    }

    public func uploaderCard(mid: Int64) async throws -> UploaderCard {
        try await get("/x/web-interface/card", query: ["mid": String(mid), "photo": "false"], signed: false)
    }

    public func like(aid: Int64, bvid: String, on: Bool) async throws {
        try await post("/x/web-interface/archive/like", form: ["aid": String(aid), "like": on ? "1" : "2"],
                       referer: videoReferer(bvid))
    }

    /// 一键三连: like, coin and favourite in one call. The server spends up to two coins and says how many.
    public func triple(aid: Int64, bvid: String) async throws -> TripleResult {
        let form = [
            "aid": String(aid),
            "eab_x": "2",
            "ramval": "0",
            "source": "web_normal",
            "ga": "1",
            "spmid": "333.788.0.0",
            "statistics": #"{"appId":100,"platform":5}"#,
        ]
        return try await post("/x/web-interface/archive/like/triple", form: form, referer: videoReferer(bvid))
    }

    public func coin(aid: Int64, bvid: String, multiply: Int, alsoLike: Bool) async throws {
        try await post("/x/web-interface/coin/add",
                       form: ["aid": String(aid), "multiply": String(multiply), "select_like": alsoLike ? "1" : "0"],
                       referer: videoReferer(bvid))
    }

    public func coinBalance() async throws -> Double {
        let balance: CoinBalance = try await get("/site/getCoin", query: [:], signed: false, host: "https://account.bilibili.com")
        return balance.money
    }

    /// The account's own folders; `contains` tells which of them already hold the video `aid`.
    public func favouriteFolders(mid: Int64, aid: Int64) async throws -> [FavFolder] {
        let list: FolderList = try await get("/x/v3/fav/folder/created/list-all",
                                             query: ["up_mid": String(mid), "rid": String(aid), "type": "2"], signed: false)
        return list.folders
    }

    /// `rid`/`type` is the single-video form and `resources` the batch form; sending both keeps either reading working.
    public func updateFavourites(aid: Int64, add: [Int64], remove: [Int64]) async throws {
        try await post("/x/v3/fav/resource/batch-deal", form: [
            "rid": String(aid),
            "type": "2",
            "resources": "\(aid):2",
            "add_media_ids": add.map(String.init).joined(separator: ","),
            "del_media_ids": remove.map(String.init).joined(separator: ","),
        ])
    }

    public func createFolder(title: String, isPrivate: Bool) async throws -> FavFolder {
        try await post("/x/v3/fav/folder/add", form: ["title": title, "privacy": isPrivate ? "1" : "0"])
    }

    public func countShare(aid: Int64) async throws {
        try await post("/x/web-interface/share/add", form: ["aid": String(aid)])
    }

    public func follow(mid: Int64, on: Bool) async throws {
        try await post("/x/relation/modify", form: ["fid": String(mid), "act": on ? "1" : "2", "re_src": "14"],
                       referer: "https://space.bilibili.com/\(mid)")
    }

    public func tags(bvid: String, cid: Int64) async throws -> [VideoTag] {
        let tags: [Lossy<VideoTag>]? = try await getIfPresent("/x/web-interface/view/detail/tag",
                                                              query: ["bvid": bvid, "cid": String(cid)], signed: false)
        return tags?.compactMap(\.value) ?? []
    }
}
