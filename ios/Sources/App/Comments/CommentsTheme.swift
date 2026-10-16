import SwiftUI

extension Theme {
    /// The 评论 tab and 评论详情, measured on the official app's screenshots (10-13) at 3x.
    enum Comments {
        /// Always light, like the official page.
        static let background = Color.white
        /// A 大会员's name; a shade off `Theme.pink` in the screenshots.
        static let vipName = hex(0xFB7299)
        static let name = Theme.secondaryText
        static let previewText = hex(0x2F3238)
        /// 回复, the thumbs and ⋮.
        static let action = hex(0x61666D)
        /// The time and IP location.
        static let meta = hex(0xC9CCD0)
        static let header = Theme.secondaryText
        static let previewBox = Theme.softGrey
        static let band = Theme.pageGrey
        static let field = Theme.pageGrey
        /// A fan card whose colour the server left out.
        static let fanNumber = hex(0x998245)
        static let viewerBackground = Color.black
        static let viewerText = Color.white

        /// LV0 to LV6. LV5 and LV6 are sampled from 13; the rest follow Bilibili's level colours.
        static let levels: [Color] = [
            hex(0xC0C4CC), hex(0xC0C4CC), hex(0x8BD29B), hex(0x7BCDEF), hex(0xFEBB8B), hex(0xEA682A), hex(0xED4D4A),
        ]

        static let avatar: CGFloat = 30
        /// The avatar under a pendant frame, which is 1.75 times its size.
        static let pendantAvatar: CGFloat = 27.5
        static let pendantScale: CGFloat = 1.75
        static let vipBadge: CGFloat = 12
        /// Where the name and text start.
        static let textLeading: CGFloat = 56
        static let avatarLeading: CGFloat = 12
        static let trailing: CGFloat = 12
        static let rowTop: CGFloat = 21
        static let fanCard = CGSize(width: 60, height: 30)
        static let fanCardTrailing: CGFloat = 21
        static let emote: CGFloat = 20
        static let pictureSpacing: CGFloat = 3
        static let pictureRadius: CGFloat = 4
        static let boxRadius: CGFloat = 8
        static let metaHeight: CGFloat = 24
        static let headerHeight: CGFloat = 28
        static let bandHeight: CGFloat = 10
        static let fieldHeight: CGFloat = 34
        static let barTop: CGFloat = 5

        static let headerFont = Font.system(size: 13)
        static let nameFont = Font.system(size: 13)
        static let textFont = Font.system(size: 15)
        static let textSize: CGFloat = 15
        static let textLineSpacing: CGFloat = 4
        static let metaFont = Font.system(size: 12)
        static let actionFont = Font.system(size: 12)
        static let thumbFont = Font.system(size: 15)
        static let previewFont = Font.system(size: 14)
        static let previewSize: CGFloat = 14
        static let moreFont = Font.system(size: 13)
        static let titleFont = Font.system(size: 15)
        static let fieldFont = Font.system(size: 14)

        static func hex(_ value: UInt32) -> Color {
            Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
        }

        /// The fan card's "#f35543"; nil for anything else.
        static func color(css: String?) -> Color? {
            guard let css, css.hasPrefix("#"), css.count == 7, let value = UInt32(css.dropFirst(), radix: 16) else { return nil }
            return hex(value)
        }
    }
}
