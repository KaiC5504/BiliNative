import Foundation

/// Ads and live rooms share the list; only `goto == "av"` rows are videos.
private struct FeedItem: Decodable {
    let card: FeedCard?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        if try container.first(String.self, "goto") == "av" {
            card = try? FeedCard(from: decoder)
        } else {
            card = nil
        }
    }
}

private struct FeedPayload: Decodable {
    let cards: [FeedCard]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let items = try container.first([Lossy<FeedItem>].self, "item") ?? []
        cards = items.compactMap { $0.value?.card }
    }
}

private struct HistoryPayload: Decodable {
    let items: [HistoryItem]
    let next: HistoryCursor?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let rows = try container.first([Lossy<HistoryItem>].self, "list") ?? []
        items = rows.compactMap(\.value)
        let cursor = container.nested("cursor")
        let max = cursor?.count("max") ?? 0
        let viewAt = cursor?.count("view_at") ?? 0
        // The last page answers with a zero cursor, and the server reads zeros as "from the top", so passing it back would loop.
        // Rows that failed to decode still count: the cursor must move past them.
        next = rows.isEmpty || (max == 0 && viewAt == 0) ? nil : HistoryCursor(max: max, viewAt: viewAt)
    }
}

extension BiliClient {
    /// `index` is the 0-based page of the endless scroll; pull to refresh starts again at 0.
    public func recommendFeed(index: Int) async throws -> [FeedCard] {
        let position = String(index)
        let query = ["fresh_type": "4", "ps": "12", "fresh_idx": position, "fresh_idx_1h": position, "brush": position,
                     "feed_version": "V8"]
        let payload: FeedPayload? = try await getIfPresent("/x/web-interface/wbi/index/top/feed/rcmd", query: query, signed: true)
        return payload?.cards ?? []
    }

    /// Needs the login cookie. `type` filters to videos and `business` names the kind of cursor row, which is then always archive.
    public func history(after cursor: HistoryCursor?) async throws -> HistoryPage {
        let query = ["max": String(cursor?.max ?? 0), "view_at": String(cursor?.viewAt ?? 0),
                     "business": "archive", "type": "archive", "ps": "20"]
        let payload: HistoryPayload? = try await getIfPresent("/x/web-interface/history/cursor", query: query, signed: false)
        return HistoryPage(items: payload?.items ?? [], next: payload?.next)
    }
}
