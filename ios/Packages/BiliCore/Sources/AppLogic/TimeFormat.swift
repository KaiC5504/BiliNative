import Foundation

public enum TimeFormat {
    public static func clock(_ seconds: Double) -> String {
        let total = seconds.isFinite ? Int(max(0, seconds)) : 0
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(two(m)):\(two(s))"
    }

    public static func pair(_ position: Double, _ duration: Double) -> String {
        "\(clock(position))/\(clock(duration))"
    }

    public static func publish(_ unix: Int64, timeZone: TimeZone = .current) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute], from: date(unix))
        return "\(c.year!)年\(c.month!)月\(c.day!)日 \(two(c.hour!)):\(two(c.minute!))"
    }

    /// Comment and feed timestamps. The 24 h cut is elapsed time; "昨天" and the date forms follow the calendar in `timeZone`.
    public static func relative(_ unix: Int64, now: Date, timeZone: TimeZone = .current) -> String {
        let elapsed = now.timeIntervalSince(date(unix))
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))分钟前" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))小时前" }

        let cal = calendar(timeZone)
        let then = date(unix)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: then)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: then), to: cal.startOfDay(for: now)).day ?? 0
        if days == 1 { return "昨天 \(two(c.hour!)):\(two(c.minute!))" }
        if c.year == cal.component(.year, from: now) { return "\(two(c.month!))-\(two(c.day!))" }
        return "\(c.year!)-\(two(c.month!))-\(two(c.day!))"
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func date(_ unix: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(unix)) }

    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
