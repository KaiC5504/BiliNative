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
        loading = true
        defer { loading = false }
        do {
            let page = try await client.history(after: cursor)
            var seen = Set(items.map(\.id))
            items += page.items.filter { seen.insert($0.id).inserted }
            cursor = page.next
            isEnd = page.next == nil || page.items.isEmpty
            error = nil
        } catch let error as BiliError where error.needsLogin {
            needsLogin = true
        } catch is CancellationError {
            return
        } catch {
            Logger.shared.warn(.ui, "history failed", ["error": .init(String(describing: error))])
            self.error = FeedModel.message(for: error)
        }
    }

    /// Starts over, as after logging in.
    func reload() async {
        guard !loading else { return }
        items = []
        cursor = nil
        isEnd = false
        needsLogin = false
        error = nil
        await loadMore()
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
