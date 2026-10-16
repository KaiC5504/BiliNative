import SwiftUI
import BiliAPI

/// Rich text renders as one `Text`, so taps arrive as link URLs: timestamps and video ids under the app's own scheme,
/// web links as themselves. An `OpenURLAction` turns the app's URLs back into runs.
enum RichLink {
    static let scheme = "bilinative"

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

    /// Nil for a web link, which the system opens.
    static func run(for url: URL) -> RichRun? {
        guard url.scheme == scheme else { return nil }
        let value = url.lastPathComponent
        switch url.host {
        case "seek":
            return Int(value).map { .timestamp(label: "", seconds: $0) }
        case "video":
            return .video(id: value)
        default:
            return nil
        }
    }

    /// Mentions are blue but lead nowhere until there is a space page; emotes stay as their tokens.
    static func attributed(_ runs: [RichRun], linkColor: Color) -> AttributedString {
        var text = AttributedString()
        for run in runs {
            var piece: AttributedString
            switch run {
            case .text(let plain):
                piece = AttributedString(plain)
            case .emote(let token, _, _):
                piece = AttributedString(token)
            case .mention(let name, _):
                piece = AttributedString(name.hasPrefix("@") ? name : "@" + name)
                piece.foregroundColor = linkColor
            case .link(let title, _):
                piece = AttributedString(title)
            case .video(let id):
                piece = AttributedString(id)
            case .timestamp(let label, _):
                piece = AttributedString(label)
            }
            if let url = url(for: run) {
                piece.link = url
                piece.foregroundColor = linkColor
            }
            text += piece
        }
        return text
    }
}
