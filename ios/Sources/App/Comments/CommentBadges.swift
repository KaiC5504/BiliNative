import SwiftUI
import UIKit

/// Characters drawn from blocks, like a seven-segment display: the level badge (LV6) and the fan card number
/// (NO. 017949) use this pixel look in the official app.
enum SegmentGlyph {
    private enum Segment { case a, b, c, d, e, f, g }

    private static let shapes: [Character: [Segment]] = [
        "0": [.a, .b, .c, .d, .e, .f], "O": [.a, .b, .c, .d, .e, .f],
        "1": [.b, .c], "2": [.a, .b, .g, .e, .d], "3": [.a, .b, .g, .c, .d], "4": [.f, .g, .b, .c],
        "5": [.a, .f, .g, .c, .d], "6": [.a, .f, .g, .e, .d, .c], "7": [.a, .b, .c], "8": [.a, .b, .c, .d, .e, .f, .g],
        "9": [.a, .b, .c, .d, .f, .g],
        // Block letters read the way a segment display writes them: N as ∩, V as U.
        "N": [.e, .f, .a, .b, .c], "L": [.f, .e, .d], "V": [.f, .e, .d, .c, .b],
    ]

    /// One character in `rect`, strokes `weight` thick; "." is a square at the bottom left.
    static func path(_ character: Character, in rect: CGRect, weight: CGFloat) -> Path {
        var path = Path()
        if character == "." {
            path.addRect(CGRect(x: rect.minX, y: rect.maxY - weight, width: weight, height: weight))
            return path
        }
        let half = rect.height / 2
        for segment in shapes[character] ?? [] {
            let r: CGRect
            switch segment {
            case .a: r = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: weight)
            case .b: r = CGRect(x: rect.maxX - weight, y: rect.minY, width: weight, height: half + weight / 2)
            case .c: r = CGRect(x: rect.maxX - weight, y: rect.minY + half - weight / 2, width: weight, height: half + weight / 2)
            case .d: r = CGRect(x: rect.minX, y: rect.maxY - weight, width: rect.width, height: weight)
            case .e: r = CGRect(x: rect.minX, y: rect.minY + half - weight / 2, width: weight, height: half + weight / 2)
            case .f: r = CGRect(x: rect.minX, y: rect.minY, width: weight, height: half + weight / 2)
            case .g: r = CGRect(x: rect.minX, y: rect.minY + half - weight / 2, width: rect.width, height: weight)
            }
            path.addRect(r)
        }
        return path
    }

    /// The advance of `character` for glyphs `width` wide; "." takes less room.
    static func advance(_ character: Character, width: CGFloat, weight: CGFloat, gap: CGFloat) -> CGFloat {
        character == "." ? weight + gap : width + gap
    }
}

/// LV0-LV6 as in 10 and 13: a block in the level's colour, the digit's part a little taller, white block letters.
struct LevelBadge: View {
    let level: Int

    static let size = CGSize(width: 18, height: 9)

    var body: some View {
        let level = min(max(level, 0), 6)
        Canvas { context, size in
            let unit = size.height / 9
            var shape = Path()
            shape.addRoundedRect(in: CGRect(x: 0, y: unit, width: 12 * unit, height: 8 * unit), cornerSize: CGSize(width: unit, height: unit))
            shape.addRoundedRect(in: CGRect(x: 11 * unit, y: 0, width: size.width - 11 * unit, height: 9 * unit),
                                 cornerSize: CGSize(width: unit, height: unit))
            context.fill(shape, with: .color(Theme.Comments.levels[level]))
            let weight = 1.15 * unit
            var glyphs = Path()
            glyphs.addPath(SegmentGlyph.path("L", in: CGRect(x: 1.3 * unit, y: 2.4 * unit, width: 3.2 * unit, height: 5.4 * unit), weight: weight))
            glyphs.addPath(SegmentGlyph.path("V", in: CGRect(x: 5.9 * unit, y: 2.4 * unit, width: 3.8 * unit, height: 5.4 * unit), weight: weight))
            glyphs.addPath(SegmentGlyph.path(Character(String(level)), in: CGRect(x: 12.5 * unit, y: 1.4 * unit, width: 4.2 * unit, height: 6.4 * unit),
                                             weight: weight))
            context.fill(glyphs, with: .color(.white))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityLabel("LV\(level)")
    }
}

/// The fan card's two lines, "NO." over the number, in the card's colour.
struct FanNumber: View {
    let number: String
    let color: Color

    private static let glyph = CGSize(width: 3.6, height: 5)
    private static let weight: CGFloat = 1.1
    private static let gap: CGFloat = 1.2
    private static let lineGap: CGFloat = 2.3

    var body: some View {
        let lines = ["NO.", number.uppercased()]
        let width = lines.map(Self.width).max() ?? 0
        Canvas { context, _ in
            var path = Path()
            for (row, line) in lines.enumerated() {
                var x: CGFloat = 0
                let y = CGFloat(row) * (Self.glyph.height + Self.lineGap)
                for character in line {
                    path.addPath(SegmentGlyph.path(character, in: CGRect(x: x, y: y, width: Self.glyph.width, height: Self.glyph.height),
                                                   weight: Self.weight))
                    x += SegmentGlyph.advance(character, width: Self.glyph.width, weight: Self.weight, gap: Self.gap)
                }
            }
            context.fill(path, with: .color(color))
        }
        .frame(width: width, height: Self.glyph.height * 2 + Self.lineGap)
        .accessibilityLabel("NO.\(number)")
    }

    private static func width(_ line: String) -> CGFloat {
        line.reduce(0) { $0 + SegmentGlyph.advance($1, width: glyph.width, weight: weight, gap: gap) } - gap
    }
}

/// An image drawn at its own aspect ratio with nothing behind it, for transparent art: pendants, fan cards.
struct DecorImage: View {
    let url: String?
    let height: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .frame(height: height)
        .task(id: url) {
            guard let url, let address = ImageLoader.secureURL(url) else { return }
            guard let loaded = await ImageLoader.shared.image(for: address) else { return }
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}

/// The comment's 置顶 mark, drawn once as an image so it sits inside the comment's `Text` and wraps with it.
@MainActor
enum PinnedTag {
    static let image: UIImage = {
        let font = UIFont.systemFont(ofSize: 11, weight: .medium)
        let label = NSAttributedString(string: "置顶", attributes: [.font: font, .foregroundColor: UIColor(Theme.pink)])
        let textSize = label.size()
        let size = CGSize(width: ceil(textSize.width) + 8, height: ceil(textSize.height) + 2)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let border = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.4, dy: 0.4), cornerRadius: 3)
            border.lineWidth = 0.8
            UIColor(Theme.pink).setStroke()
            border.stroke()
            label.draw(at: CGPoint(x: 4, y: 1))
        }
    }()
}
