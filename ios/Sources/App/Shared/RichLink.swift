import SwiftUI
import BiliAPI

/// Rich text renders as one `Text` (`RichTextView`), so taps arrive as link URLs: timestamps and video ids under the
/// app's own scheme, web links as themselves. An `OpenURLAction` turns the app's URLs back into runs.
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
}
