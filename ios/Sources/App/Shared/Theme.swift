import SwiftUI

/// Colours and sizes sampled from the official app's screenshots, so views never carry literals.
enum Theme {
    static let pink = rgb(0xFF6699)
    static let pinkTint = pink.opacity(0.12)
    static let text = rgb(0x18191C)
    static let secondaryText = rgb(0x9499A0)
    static let pageGrey = rgb(0xF1F2F3)
    /// The fill behind the collection row, tag chips and reply previews on the video page.
    static let softGrey = rgb(0xF6F7F8)
    static let divider = rgb(0xE3E5E7)
    static let link = rgb(0x00699D)
    static let card = rgb(0xFFFFFF)
    /// The feed's 推荐 reason and 竖屏 tag (01) are orange-red, not the pink accent.
    static let reason = rgb(0xFF6633)
    static let reasonTint = rgb(0xFFF1ED)
    /// Counts, durations and progress drawn over covers.
    static let onCover = Color.white
    static let coverShade = Color.black.opacity(0.5)
    static let scrim = Color.black.opacity(0.2)

    static let panel = Color.black.opacity(0.92)
    static let panelCard = rgb(0x212327)
    static let panelText = Color.white
    static let panelSecondary = rgb(0x9499A0)

    enum Metrics {
        static let gutter: CGFloat = 12
        static let cardRadius: CGFloat = 6
        static let pillHeight: CGFloat = 30
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
