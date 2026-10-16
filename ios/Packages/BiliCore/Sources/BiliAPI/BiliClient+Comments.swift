import Foundation

extension BiliClient {
    /// `offset` is the previous page's `nextOffset`; nil or empty asks for the first page.
    public func comments(aid: Int64, sort: CommentSort, offset: String? = nil) async throws -> CommentPage {
        let offset = offset ?? ""
        let query = ["oid": String(aid), "type": "1", "mode": String(sort.rawValue),
                     "pagination_str": Self.paginationString(offset: offset)]
        let data: CommentListData
        do {
            data = try await get("/x/v2/reply/wbi/main", query: query, signed: true)
        } catch let error where Self.isRiskControl(error) {
            data = try await get("/x/v2/reply/main", query: query, signed: false)
        }
        var page = data.page
        if !offset.isEmpty { page.pinned = nil }
        return page
    }

    public func thread(aid: Int64, root: Int64, page: Int, sort: CommentSort = .time) async throws -> ThreadPage {
        let query = ["oid": String(aid), "type": "1", "root": String(root), "pn": String(page), "ps": "20",
                     "sort": String(sort.threadSort)]
        let data: CommentThreadData = try await get("/x/v2/reply/reply", query: query, signed: false)
        return data.page
    }

    /// `root` and `parent` stay 0 for a top-level comment; a reply to a reply sets `parent` to that reply.
    public func postComment(aid: Int64, message: String, root: Int64 = 0, parent: Int64 = 0,
                            syncToDynamic: Bool = false) async throws -> Comment {
        var form = ["oid": String(aid), "type": "1", "message": message]
        if root != 0 { form["root"] = String(root) }
        if parent != 0 { form["parent"] = String(parent) }
        if syncToDynamic { form["sync_to_dynamic"] = "1" }
        let posted: PostedComment = try await post("/x/v2/reply/add", form: form,
                                                   referer: "https://www.bilibili.com/video/av\(aid)")
        return posted.reply
    }

    public func likeComment(aid: Int64, rpid: Int64, on: Bool) async throws {
        try await post("/x/v2/reply/action", form: reaction(aid: aid, rpid: rpid, on: on))
    }

    public func hateComment(aid: Int64, rpid: Int64, on: Bool) async throws {
        try await post("/x/v2/reply/hate", form: reaction(aid: aid, rpid: rpid, on: on))
    }

    public func deleteComment(aid: Int64, rpid: Int64) async throws {
        try await post("/x/v2/reply/del", form: ["oid": String(aid), "type": "1", "rpid": String(rpid)])
    }

    public func emotePackages() async throws -> [EmotePackage] {
        let panel: EmotePanel = try await get("/x/emote/user/panel/web", query: ["business": "reply"], signed: false)
        return panel.packages
    }

    private func reaction(aid: Int64, rpid: Int64, on: Bool) -> [String: String] {
        ["oid": String(aid), "type": "1", "rpid": String(rpid), "action": on ? "1" : "0"]
    }

    private static func paginationString(offset: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(["offset": offset])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The signed route is the newer one; risk control sometimes refuses it while the plain route still answers.
    private static func isRiskControl(_ error: Error) -> Bool {
        switch error as? BiliError {
        case .api(let code, _)?: return code == -352 || code == -403
        case .http(let status)?: return status == 412
        default: return false
        }
    }
}
