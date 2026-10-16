import CoreText
import SwiftUI
import UIKit
import BiliShared
import DevLog

/// The three danmaku glyphs from PiliPlus's custom_icon.ttf, and its coin-dialog art. Both ship as plain
/// files in `Resources/Borrowed`; see CLAUDE.md for why they are in this repo.
enum BorrowedIcon: CaseIterable {
    case danmakuOn, danmakuOff, danmakuSettings

    static let fontName = "custom_icon"

    private static let rendered = Locked<[BorrowedIcon: UIImage]>([:])

    private var codePoint: UInt16 {
        switch self {
        case .danmakuOff: 0xE801
        case .danmakuOn: 0xE802
        case .danmakuSettings: 0xE803
        }
    }

    private var symbolName: String {
        switch self {
        case .danmakuOn: "text.bubble"
        case .danmakuOff: "text.bubble.slash"
        case .danmakuSettings: "gearshape"
        }
    }

    /// Template image: tint it with `foregroundStyle`, size it with `resizable()`.
    var image: Image {
        Image(uiImage: uiImage()).renderingMode(.template)
    }

    func uiImage(fontName: String = BorrowedIcon.fontName) -> UIImage {
        let isDefault = fontName == Self.fontName
        if isDefault, let cached = Self.rendered.current[self] { return cached }
        if let glyph = glyphImage(fontName: fontName) {
            if isDefault { Self.rendered.withLock { $0[self] = glyph } }
            return glyph
        }
        // Not every symbol exists on every iOS version; the plain bubble always does.
        return UIImage(systemName: symbolName) ?? UIImage(systemName: "text.bubble") ?? UIImage()
    }

    /// Nil when the font is not registered or has no glyph at the code point.
    func glyphImage(pointSize: CGFloat = 48, fontName: String = BorrowedIcon.fontName) -> UIImage? {
        guard let font = UIFont(name: fontName, size: pointSize) else { return nil }
        let ctFont = CTFontCreateWithName(font.fontName as CFString, pointSize, nil)
        var character = codePoint
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1), glyph != 0 else { return nil }
        let bounds = CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, nil, 1)
        let side = pointSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            let cg = context.cgContext
            // CoreText draws with the y axis up.
            cg.translateBy(x: 0, y: side)
            cg.scaleBy(x: 1, y: -1)
            var origin = CGPoint(x: (side - bounds.width) / 2 - bounds.minX, y: (side - bounds.height) / 2 - bounds.minY)
            CTFontDrawGlyphs(ctFont, &glyph, &origin, 1, cg)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    static func registerFont() {
        guard let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") else {
            Logger.shared.warn(.app, "icon font is not in the bundle; danmaku icons use SF Symbols")
            return
        }
        var error: Unmanaged<CFError>?
        guard !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { return }
        let failure = error?.takeRetainedValue()
        // Registering twice (a second scene, a test host) reports an error that changes nothing.
        guard failure.map({ CFErrorGetCode($0) != CTFontManagerError.alreadyRegistered.rawValue }) ?? true else { return }
        Logger.shared.warn(.app, "icon font did not register", ["error": .init(failure.map { String(describing: $0) } ?? "unknown")])
    }

    /// A PNG from `Resources/Borrowed`, by file name without extension. Files have no @2x or @3x variants, so size them with `resizable()`.
    static func art(_ name: String) -> UIImage? {
        UIImage(named: name, in: .main, compatibleWith: nil)
    }
}
