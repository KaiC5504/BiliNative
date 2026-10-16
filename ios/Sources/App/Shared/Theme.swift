import SwiftUI

/// Colours and sizes sampled from the official app's screenshots, so views never carry literals.
enum Theme {
    static let pink = Color(hex: 0xFF6699)
    static let pinkTint = pink.opacity(0.12)
    static let text = Color(hex: 0x18191C)
    static let secondaryText = Color(hex: 0x9499A0)
    static let pageGrey = Color(hex: 0xF1F2F3)
    /// The fill behind the collection row, tag chips and reply previews on the video page.
    static let softGrey = Color(hex: 0xF6F7F8)
    static let divider = Color(hex: 0xE3E5E7)
    static let link = Color(hex: 0x00699D)

    static let panel = Color.black.opacity(0.92)
    static let panelCard = Color(hex: 0x212327)
    static let panelText = Color.white
    static let panelSecondary = Color(hex: 0x9499A0)

    enum Metrics {
        static let gutter: CGFloat = 12
        static let cardRadius: CGFloat = 6
        static let pillHeight: CGFloat = 30
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
