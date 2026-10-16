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
        /// 25 pt from line to line in 12.
        static let textLineSpacing: CGFloat = 7
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

    /// The comment composer and its emote panel, measured on 14 (a 440 pt wide phone at 3x).
    enum Composer {
        private static let hex = Comments.hex

        /// The page behind the sheet: white reads as #CCCCCC in 14.
        static let dim = Color.black.opacity(0.2)
        static let sheet = Color.white
        /// The keyboard toggle and 发布 are a deeper pink than `Theme.pink` in 14; 发布 without text is it at 30%.
        static let accent = hex(0xED7098)
        static let accentFaded = accent.opacity(0.3)
        static let publishText = Color.white
        static let placeholder = Comments.meta
        static let tool = Comments.action
        static let syncRing = Comments.meta
        static let expand = Theme.secondaryText
        static let panel = Theme.pageGrey
        static let tabBar = Color.white
        static let tabSelected = Theme.pageGrey
        static let sectionTitle = Comments.action
        static let kaomojiTab = hex(0xA7A7A7)
        static let kaomoji = Theme.text

        static let sheetRadius: CGFloat = 4
        static let editorHeight: CGFloat = 68
        static let expandedEditorHeight: CGFloat = 260
        static let editorTop: CGFloat = 13
        static let editorLeading: CGFloat = 12
        /// Room on the right for the expand arrow.
        static let editorTrailing: CGFloat = 40
        static let expandIcon: CGFloat = 11
        static let toolbarHeight: CGFloat = 46
        static let syncLeading: CGFloat = 11
        static let syncCircle: CGFloat = 10
        static let syncGap: CGFloat = 5
        /// Ends where the keyboard toggle's 30 pt cell starts, so the toggle sits 96 pt from the edge.
        static let syncWidth: CGFloat = 70
        static let toggleWidth: CGFloat = 30
        static let keyboardIcon = CGSize(width: 20, height: 16)
        static let publish = CGSize(width: 56, height: 24)
        static let publishTrailing: CGFloat = 12

        static let panelHeight: CGFloat = 226
        static let tabHeight: CGFloat = 44
        static let tabWidth: CGFloat = 50
        static let tabIcon: CGFloat = 27
        static let sectionHeight: CGFloat = 34
        static let gridSide: CGFloat = 3
        static let columns = 7
        static let emote: CGFloat = 28
        static let row: CGFloat = 61
        /// 最近使用 is one row with less room under it than the grid's rows.
        static let recentRow: CGFloat = 54
        static let largeColumns = 4
        static let largeEmote: CGFloat = 52
        static let largeRow: CGFloat = 80
        static let textColumns = 3
        static let textRow: CGFloat = 44

        static let editorFont = Font.system(size: 16)
        static let syncFont = Font.system(size: 10)
        static let publishFont = Font.system(size: 13)
        static let sectionFont = Font.system(size: 12)
        static let kaomojiTabFont = Font.system(size: 9)
        static let kaomojiFont = Font.system(size: 13)
    }
}
