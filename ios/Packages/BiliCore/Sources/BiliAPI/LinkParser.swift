import Foundation

public enum VideoLink: Equatable, Sendable {
    case bvid(String, page: Int?)
    case aid(Int64, page: Int?)
    case short(URL)

    public var isShort: Bool {
        if case .short = self { return true }
        return false
    }
}

public enum LinkParser {
    private static let shortPattern = try! NSRegularExpression(pattern: #"https?://(?:b23\.tv|bili2233\.cn)/[A-Za-z0-9]+"#)
    private static let pagePattern = try! NSRegularExpression(pattern: #"[?&]p=(\d+)"#)
    private static let bvPattern = try! NSRegularExpression(pattern: #"BV1[0-9A-Za-z]{9}(?![0-9A-Za-z])"#)
    private static let avPattern = try! NSRegularExpression(pattern: #"(?i)(?:^|[^a-z0-9])av(\d+)"#)

    /// Finds a video in anything a user might paste: a URL, a bare id, or the share text of the official app.
    public static func parse(_ text: String) -> VideoLink? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = first(shortPattern, in: input), let url = URL(string: match) {
            return .short(url)
        }
        let page = first(pagePattern, group: 1, in: input).flatMap { Int($0) }
        if let bv = first(bvPattern, in: input) {
            return .bvid(bv, page: page)
        }
        if let av = first(avPattern, group: 1, in: input), let id = Int64(av) {
            return .aid(id, page: page)
        }
        return nil
    }

    private static func first(_ regex: NSRegularExpression, group: Int = 0, in text: String) -> String? {
        let ns = NSString(string: text)
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }
}
