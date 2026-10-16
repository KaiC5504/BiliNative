import Foundation
import BiliAPI

public enum HistoryGrouping {
    /// One section per calendar day in `timeZone`, in the order the days first appear. The history list is already newest first.
    public static func sections(_ items: [HistoryItem], now: Date,
                                timeZone: TimeZone = .current) -> [(title: String, items: [HistoryItem])] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: now)

        var order: [Date] = []
        var byDay: [Date: [HistoryItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(item.viewAt)))
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(item)
        }

        return order.map { day in
            let age = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let title: String
            if age == 0 {
                title = "今天"
            } else if age == 1 {
                title = "昨天"
            } else {
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                let monthDay = "\(parts.month ?? 1)月\(parts.day ?? 1)日"
                title = parts.year == thisYear ? monthDay : "\(parts.year ?? thisYear)年\(monthDay)"
            }
            return (title: title, items: byDay[day] ?? [])
        }
    }
}
