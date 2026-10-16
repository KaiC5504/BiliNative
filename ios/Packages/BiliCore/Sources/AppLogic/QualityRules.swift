import Foundation

public enum QualityRules {
    /// Bilibili's qn values from 112 (1080P+) up are paid-member only.
    public static func needsVip(_ qn: Int) -> Bool { qn >= 112 }

    public static func auto(offered: [Int], isVip: Bool) -> Int? {
        offered.filter { isVip || !needsVip($0) }.max()
    }
}
