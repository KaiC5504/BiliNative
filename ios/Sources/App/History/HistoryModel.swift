import Foundation
import Observation
import AppLogic
import BiliAPI
import DevLog

struct HistorySection: Identifiable {
    let title: String
    let items: [HistoryItem]
    var id: String { title }
}

/// 历史记录 (28), 视频 only: pages through the cursor until Bilibili answers with an empty page.
@MainActor
@Observable
final class HistoryModel {
    private(set) var items: [HistoryItem] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var isEnd = false
    /// Bilibili answered -101: the cookies are gone or expired.
    private(set) var needsLogin = false

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var cursor: HistoryCursor?
    /// Bumped by a reload, so a load more still running cannot append to the new list.
    @ObservationIgnored private var generation = 0

    init(client: BiliClient, now: @escaping () -> Date = Date.init, timeZone: TimeZone = .current) {
        self.client = client
        self.now = now
        self.timeZone = timeZone
    }

    var sections: [HistorySection] {
        HistoryGrouping.sections(items, now: now(), timeZone: timeZone).map { HistorySection(title: $0.title, items: $0.items) }
    }

    func loadMore() async {
        guard !loading, !isEnd, !needsLogin else { return }
        await load(replacing: false)
    }

    /// Starts over, as after logging in and on pull to refresh. The rows already shown stay until the first page
    /// answers, so the list (and the scroll view running the refresh) never goes away mid-pull.
    func reload() async {
        generation += 1
        needsLogin = false
        error = nil
        await load(replacing: true)
    }

    private func load(replacing: Bool) async {
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        var next = replacing ? nil : cursor
        var kept = replacing ? [] : items
        do {
            // A page of videos already listed adds no row, so no row appears to ask for the next; ask on, a few times.
            for _ in 0..<3 {
                let page = try await client.history(after: next)
                guard mine == generation else { return }
                var seen = Set(kept.map(\.id))
                let fresh = page.items.filter { seen.insert($0.id).inserted }
                kept += fresh
                next = page.next
                isEnd = page.next == nil || page.items.isEmpty
                if !fresh.isEmpty || isEnd { break }
            }
            items = kept
            cursor = next
            error = nil
        } catch let error as BiliError where error.needsLogin {
            guard mine == generation else { return }
            needsLogin = true
        } catch where FeedModel.isCancellation(error) {
            return
        } catch {
            guard mine == generation else { return }
            Logger.shared.warn(.ui, "history failed", ["error": .init(String(describing: error))])
            self.error = FeedModel.message(for: error)
        }
    }

    /// A finished video (progress -1) starts again from the beginning.
    static func route(for item: HistoryItem) -> VideoRoute {
        VideoRoute(bvid: item.bvid, cid: item.cid, startSeconds: item.progress < 0 ? 0 : Double(item.progress))
    }

    /// "00:02/02:12" on the cover, or 已看完.
    static func progressLabel(for item: HistoryItem) -> String {
        item.progress < 0 ? "已看完" : TimeFormat.pair(Double(item.progress), Double(item.duration))
    }

    /// How much of the pink bar under the cover is filled.
    static func progressFraction(for item: HistoryItem) -> Double {
        guard item.progress >= 0 else { return 1 }
        guard item.duration > 0 else { return 0 }
        return min(1, Double(item.progress) / Double(item.duration))
    }

    /// Today and yesterday show the time alone, since the section already names the day; older ones the full date.
    static func timeLabel(_ viewAt: Int64, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let then = Date(timeIntervalSince1970: TimeInterval(viewAt))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: then), to: calendar.startOfDay(for: now)).day ?? 0
        guard days <= 1 else { return TimeFormat.publish(viewAt, timeZone: timeZone) }
        let parts = calendar.dateComponents([.hour, .minute], from: then)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    func timeLabel(for item: HistoryItem) -> String {
        Self.timeLabel(item.viewAt, now: now(), timeZone: timeZone)
    }

    static func deviceSymbol(_ kind: HistoryDeviceKind) -> String {
        switch kind {
        case .phone: return "iphone"
        case .pc: return "desktopcomputer"
        case .padOrTV: return "ipad.landscape"
        }
    }
}
