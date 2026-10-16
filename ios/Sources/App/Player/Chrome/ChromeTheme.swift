import SwiftUI

extension Theme {
    /// The player's controls, measured on the official app's screenshots (15, 04, 09, 25, 26, 27) at 3x.
    enum Chrome {
        static let track = Color.white.opacity(0.2)
        static let buffered = Color.white.opacity(0.4)
        static let tick = Color.black.opacity(0.7)
        static let verticalTrack = Color.white.opacity(0.15)
        static let verticalPlayed = Color.white.opacity(0.6)
        static let thumbRim = Theme.pink.opacity(0.3)
        static let secondary = Color.white.opacity(0.6)
        static let faint = Color.white.opacity(0.35)
        /// The shade behind the HUD pills (25).
        static let hudFill = Color.black.opacity(0.55)
        /// Top and bottom shading behind the small player's controls.
        static let shade = Color.black.opacity(0.45)
        /// The dim over the last frame on the end screens.
        static let endDim = Color.black.opacity(0.62)
        static let endButton = Color.white.opacity(0.22)
        static let divider = Color.white.opacity(0.15)
        /// The landscape danmaku field (04) and its placeholder.
        static let field = Color.white.opacity(0.8)
        static let fieldText = Color(white: 0.38)
        /// The 竖屏 发弹幕 field (09).
        static let darkField = Color(white: 0.15)
        static let darkFieldText = Color.white.opacity(0.45)

        static let button: CGFloat = 44
        static let barHeight: CGFloat = 2
        static let barTouchHeight: CGFloat = 24
        static let thumbSize = CGSize(width: 18, height: 16)
        static let verticalDot: CGFloat = 5
        static let hiddenLine: CGFloat = 2
        static let hideDelay: Double = 3

        static let timeFont = Font.system(size: 12).monospacedDigit()
        static let titleFont = Font.system(size: 17, weight: .medium)
        static let labelFont = Font.system(size: 15)
        static let smallFont = Font.system(size: 13)
        static let hudFont = Font.system(size: 16)
        static let iconFont = Font.system(size: 20)
        static let playFont = Font.system(size: 20)
        static let landscapePlayFont = Font.system(size: 23)
    }
}
