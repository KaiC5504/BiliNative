import SwiftUI

extension Theme {
    /// The page under the small player, measured on the official app's screenshots (03, 10, 18, 19) at 3x.
    enum Page {
        /// Always light, like the official page; Theme's text colours are fixed dark.
        static let background = Color.white
        static let tabText = Color(.sRGB, red: 0x61 / 255, green: 0x66 / 255, blue: 0x6D / 255)
        static let chipText = tabText
        static let faintText = Color(.sRGB, red: 0xC9 / 255, green: 0xCC / 255, blue: 0xD0 / 255)
        static let grabber = faintText
        static let forbidden = Color(.sRGB, red: 0xF8 / 255, green: 0x5A / 255, blue: 0x54 / 255)
        static let durationFill = Color.black.opacity(0.55)
        static let collapsedShade = Color.black.opacity(0.72)
        static let sheetShadow = Color.black.opacity(0.08)

        static let tabRowHeight: CGFloat = 40
        static let avatar: CGFloat = 30
        static let relatedThumb = CGSize(width: 128, height: 72)
        static let episodeThumb = CGSize(width: 134, height: 76)
        static let chipHeight: CGFloat = 25
        static let sheetRadius: CGFloat = 16

        static let titleFont = Font.system(size: 16, weight: .semibold)
        static let bodyFont = Font.system(size: 15)
        static let metaFont = Font.system(size: 13)
        static let smallFont = Font.system(size: 12)
    }
}
