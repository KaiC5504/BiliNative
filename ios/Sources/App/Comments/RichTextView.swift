import SwiftUI
import UIKit
import BiliAPI

/// What a tap on rich text does. The page sets it once, for the description and every comment.
struct RichTextActions {
    var seek: (Int) -> Void = { _ in }
    var openVideo: (String) -> Void = { _ in }
}

private struct RichTextActionsKey: EnvironmentKey {
    static let defaultValue = RichTextActions()
}

extension EnvironmentValues {
    var richTextActions: RichTextActions {
        get { self[RichTextActionsKey.self] }
        set { self[RichTextActionsKey.self] = newValue }
    }
}

/// Rich text as one `Text`, so it wraps and truncates like plain text: emotes are inline images, mentions and links
/// are blue, and timestamps and video ids are links under the app's own scheme that the `OpenURLAction` turns back
/// into a seek or a pushed page.
struct RichTextView: View {
    static let scheme = "bilinative"

    let runs: [RichRun]
    var font = Theme.Comments.textFont
    var fontSize = Theme.Comments.textSize
    var color = Theme.text
    var lineSpacing = Theme.Comments.textLineSpacing
    var lineLimit: Int?
    /// Goes in front of the runs inside the same `Text`, such as a preview reply's "名字: " or the 置顶 tag.
    var prefix: Text?
    @Environment(\.richTextActions) private var actions
    @State private var emotes: [String: UIImage] = [:]

    var body: some View {
        composed
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .lineLimit(lineLimit)
            // Links take the tint, whatever their own colour says.
            .tint(Theme.link)
            .environment(\.openURL, OpenURLAction { url in
                open(url) ? .handled : .systemAction
            })
            .task(id: emoteKeys) { await loadEmotes() }
    }

    private var composed: Text {
        var text = prefix ?? Text(verbatim: "")
        var pending = AttributedString()
        for run in runs {
            if case .emote(let token, let url, let size) = run {
                if !pending.characters.isEmpty {
                    text = Text("\(text)\(Text(pending))")
                    pending = AttributedString()
                }
                text = Text("\(text)\(emote(token: token, url: url, size: size))")
            } else {
                pending += Self.attributed(run)
            }
        }
        if !pending.characters.isEmpty { text = Text("\(text)\(Text(pending))") }
        return text
    }

    private func emote(token: String, url: String, size: Int) -> Text {
        let side = Theme.Comments.emote * CGFloat(max(size, 1))
        let image = emotes[Self.key(url, side)] ?? EmoteCache.blank(side)
        // Centred on the text rather than standing on its baseline.
        return Text(Image(uiImage: image)).baselineOffset(-(side - fontSize * 0.7) / 2)
            .accessibilityLabel(token)
    }

    private var emoteKeys: [String] {
        runs.compactMap { run in
            guard case .emote(_, let url, let size) = run else { return nil }
            return Self.key(url, Theme.Comments.emote * CGFloat(max(size, 1)))
        }
    }

    private func loadEmotes() async {
        for run in runs {
            guard case .emote(_, let url, let size) = run else { continue }
            let side = Theme.Comments.emote * CGFloat(max(size, 1))
            let key = Self.key(url, side)
            guard emotes[key] == nil, let image = await EmoteCache.image(url, side: side) else { continue }
            emotes[key] = image
        }
    }

    private static func key(_ url: String, _ side: CGFloat) -> String { "\(Int(side))|\(url)" }

    static func attributed(_ run: RichRun) -> AttributedString {
        var piece: AttributedString
        switch run {
        case .text(let plain):
            return AttributedString(plain)
        case .emote(let token, _, _):
            return AttributedString(token)
        case .mention(let name, _):
            piece = AttributedString(name.hasPrefix("@") ? name : "@" + name)
            piece.foregroundColor = Theme.link
            return piece
        case .link(let title, _):
            piece = AttributedString(title)
        case .video(let id):
            piece = AttributedString(id)
        case .timestamp(let label, _):
            piece = AttributedString(label)
        }
        if let url = url(for: run) {
            piece.link = url
            piece.foregroundColor = Theme.link
        }
        return piece
    }

    static func url(for run: RichRun) -> URL? {
        switch run {
        case .timestamp(_, let seconds):
            return URL(string: "\(scheme)://seek/\(seconds)")
        case .video(let id) where id.hasPrefix("BV"):
            return URL(string: "\(scheme)://video/\(id)")
        case .link(_, let url):
            return URL(string: url)
        default:
            return nil
        }
    }

    /// False for a web link that is not a video, which Safari opens.
    private func open(_ url: URL) -> Bool {
        if url.scheme == Self.scheme {
            let value = url.lastPathComponent
            switch url.host {
            case "seek": Int(value).map(actions.seek)
            case "video": actions.openVideo(value)
            default: break
            }
            return true
        }
        if let host = url.host, host.hasSuffix("bilibili.com"), url.path.hasPrefix("/video/"),
           case .bvid(let bvid, _)? = LinkParser.parse(url.absoluteString) {
            actions.openVideo(bvid)
            return true
        }
        return false
    }

    /// A reply inside a thread starts "回复 @名字 :". When the server sent no mid for that name the runs keep it as
    /// text, so the name is made a mention here and is blue like the others.
    static func markingReplyTarget(_ runs: [RichRun]) -> [RichRun] {
        let lead = "回复 @"
        guard case .text(let first)? = runs.first, first.hasPrefix(lead) else { return runs }
        let rest = first.dropFirst(lead.count)
        guard let colon = rest.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return runs }
        let name = rest[..<colon].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return runs }
        let after = String(rest[colon...])
        let trailing = rest[..<colon].hasSuffix(" ") ? " " : ""
        return [.text("回复 "), .mention(name: name, mid: 0), .text(trailing + after)] + runs.dropFirst()
    }
}

/// Emotes resized once to the point size they are drawn at; `Text(Image)` draws an image at its own size.
@MainActor
enum EmoteCache {
    private static let sized = NSCache<NSString, UIImage>()
    private static var blanks: [CGFloat: UIImage] = [:]

    static func image(_ url: String, side: CGFloat) async -> UIImage? {
        let key = "\(Int(side))|\(url)" as NSString
        if let hit = sized.object(forKey: key) { return hit }
        guard let address = ImageLoader.secureURL(url), let source = await ImageLoader.shared.image(for: address) else {
            return nil
        }
        let image = fitted(source, side: side)
        sized.setObject(image, forKey: key)
        return image
    }

    /// Holds the emote's place while it loads, so the text does not reflow when it arrives.
    static func blank(_ side: CGFloat) -> UIImage {
        if let blank = blanks[side] { return blank }
        let blank = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in }
        blanks[side] = blank
        return blank
    }

    private static func fitted(_ source: UIImage, side: CGFloat) -> UIImage {
        let size = source.size
        let scale = min(side / max(size.width, 1), side / max(size.height, 1))
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            source.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
    }
}
