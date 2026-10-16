import Foundation
import Observation
import BiliAPI
import DevLog

/// The 推荐 feed: page 1 on refresh, then the next index for every load more.
@MainActor
@Observable
final class FeedModel {
    private(set) var cards: [FeedCard] = []
    private(set) var loading = false
    /// The last load failed; endless scroll waits for a tap on retry instead of asking again by itself.
    private(set) var error: String?

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private var nextIndex = 1
    /// A refresh replaces the list, so a load more that was already running must not append to the new one.
    @ObservationIgnored private var generation = 0

    init(client: BiliClient) {
        self.client = client
    }

    func refresh() async {
        generation += 1
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            // The first launch reaches here before the account check has fetched the fingerprint cookies.
            try await client.ensureRiskCookies()
            let page = try await client.recommendFeed(index: 1)
            guard mine == generation else { return }
            cards = Self.appending(page, to: [])
            nextIndex = 2
            error = nil
        } catch {
            guard mine == generation, !Self.isCancellation(error) else { return }
            Logger.shared.warn(.ui, "feed refresh failed", ["error": .init(String(describing: error))])
            self.error = Self.message(for: error)
        }
    }

    func loadMore() async {
        guard !loading else { return }
        guard !cards.isEmpty else { return await refresh() }
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            // A page of cards already shown (or only ads) adds nothing, and then no card appears to ask for the
            // next one; ask on, a few times.
            for _ in 0..<3 {
                let page = try await client.recommendFeed(index: nextIndex)
                guard mine == generation else { return }
                let before = cards.count
                cards = Self.appending(page, to: cards)
                nextIndex += 1
                if cards.count > before { break }
            }
            error = nil
        } catch {
            guard mine == generation, !Self.isCancellation(error) else { return }
            Logger.shared.warn(.ui, "feed load more failed", ["index": .init(nextIndex), "error": .init(String(describing: error))])
            self.error = Self.message(for: error)
        }
    }

    /// The feed repeats videos across pages, and a grid keyed by bvid must not hold one twice.
    private static func appending(_ page: [FeedCard], to cards: [FeedCard]) -> [FeedCard] {
        var seen = Set(cards.map(\.bvid))
        return cards + page.filter { seen.insert($0.bvid).inserted }
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static func message(for error: Error) -> String {
        if let error = error as? BiliError { return error.userMessage }
        if error is URLError { return "网络连接失败，请检查网络后重试" }
        return "加载失败，请稍后重试"
    }
}
