import Foundation

public enum CountFormat {
    /// Bilibili's compact counts. Truncates rather than rounds so 99 999 999 never reads as 10000万.
    public static func short(_ n: Int64) -> String {
        if n < 10_000 { return String(n) }
        if n < 100_000_000 { return scaled(n / 1_000, unit: "万") }
        return scaled(n / 10_000_000, unit: "亿")
    }

    private static func scaled(_ tenths: Int64, unit: String) -> String {
        let whole = tenths / 10, fraction = tenths % 10
        return fraction == 0 ? "\(whole)\(unit)" : "\(whole).\(fraction)\(unit)"
    }
}
