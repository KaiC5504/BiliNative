import Foundation

/// The official app's names for Bilibili's qn values. The playurl's own descriptions read differently
/// ("超清 4K", "清晰 480P"), so the app shows these and falls back to the server's text for a qn missing here.
public enum QualityNames {
    // 125 to 64 were read off the official app's 清晰度 picker and 32 from a later look at it. 127, 126, 112, 74
    // and 16 have not been seen there yet; they follow its naming and get corrected when they are.
    private static let fullNames: [Int: String] = [
        127: "8K 超高清",
        126: "杜比视界",
        125: "HDR 真彩",
        120: "4K 超高清",
        116: "1080P 60帧",
        112: "1080P+ 高码率",
        80: "1080P 高清",
        74: "720P 60帧",
        64: "720P 准高清",
        32: "480P 标清",
        16: "360P 流畅",
    ]

    /// What the player's quality button shows: the official app prints just "4K" there.
    private static let shortNames: [Int: String] = [
        127: "8K",
        126: "杜比视界",
        125: "HDR",
        120: "4K",
        116: "1080P60",
        112: "1080P+",
        80: "1080P",
        74: "720P60",
        64: "720P",
        32: "480P",
        16: "360P",
        6: "240P",
    ]

    public static func full(qn: Int, serverText: String?) -> String {
        fullNames[qn] ?? serverText ?? String(qn)
    }

    public static func short(qn: Int, serverText: String?) -> String {
        shortNames[qn] ?? serverText?.split(separator: " ").last.map(String.init) ?? "清晰度"
    }
}
