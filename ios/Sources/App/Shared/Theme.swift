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

    static let toastFill = Color.black.opacity(0.92)
    /// How dark the layer behind a panel is once it is fully in, as a share of black.
    static let panelShadeOpacity = 0.86
    static let panelShade = Color.black.opacity(panelShadeOpacity)
    /// Share of black at 0, 35, 70 and 100 per cent of the ramp that leads into a panel; the official app's frames
    /// give a slow start and about 0.74 where the cards begin.
    static let panelFade: [(location: CGFloat, black: Double)] = [(0, 0), (0.35, 0.2), (0.7, 0.55), (1, 0.74)]
    /// Over black this lands on the official #212327; over a bright video it lifts a few levels, as theirs does.
    static let panelCard = rgb(0x2B2C30).opacity(0.8)
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
