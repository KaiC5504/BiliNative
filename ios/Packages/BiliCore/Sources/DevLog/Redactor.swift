import Foundation

public enum Redactor {
    static let secretNames: Set<String> = [
        "sessdata", "bili_jct", "csrf", "cookie", "set-cookie", "authorization", "access_key", "refresh_token", "dedeuserid__ckmd5",
    ]
    private static let idNames: Set<String> = ["mid", "dedeuserid"]
    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s"'<>]+"#)
    private static let urlTrailing = CharacterSet(charactersIn: ").,;!?]}")
    private static let authorizationPattern = try! NSRegularExpression(
        pattern: #"(?i)\b((?:proxy-)?authorization["']?\s*[:=]\s*["']?)[^\r\n"']+"#)
    private static let cookieHeaderPattern = try! NSRegularExpression(
        pattern: #"(?i)\b((?:set-)?cookie["']?\s*:\s*["']?)([^\r\n"']+)"#)
    private static let csrfPattern = try! NSRegularExpression(
        pattern: #"(?i)\b([\w-]*csrf[\w-]*["']?\s*[=:]\s*["']?)[^;&\s"',]+"#)
    private static let pairPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(SESSDATA|bili_jct|csrf|access_key|refresh_token|DedeUserID__ckMd5)=([^;&\s"]+)"#)
    private static let cookieFlags: Set<String> = ["httponly", "secure", "partitioned"]

    public static func fields(_ fields: [String: LogValue]) -> [String: LogValue] {
        var result: [String: LogValue] = [:]
        for (key, value) in fields {
            let lowered = key.lowercased()
            if secretNames.contains(lowered) || lowered.contains("csrf") {
                result[key] = .string("[redacted]")
            } else if idNames.contains(lowered) {
                result[key] = .string(hashedID(value))
            } else if case .string(let text) = value {
                result[key] = .string(Self.text(text))
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// Shortens signed URLs and blanks cookie-style secrets in free text.
    public static func text(_ input: String) -> String {
        var output = replace(urlPattern, in: input) { match, _ in
            var core = match
            var tail = ""
            while let last = core.unicodeScalars.last, urlTrailing.contains(last) {
                core.unicodeScalars.removeLast()
                tail = String(last) + tail
            }
            return url(core) + tail
        }
        output = replace(authorizationPattern, in: output) { _, groups in groups[0] + "[redacted]" }
        output = replace(cookieHeaderPattern, in: output) { _, groups in groups[0] + redactCookieValues(groups[1]) }
        output = replace(csrfPattern, in: output) { _, groups in groups[0] + "[redacted]" }
        return replace(pairPattern, in: output) { match, _ in
            let name = match.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "secret"
            return "\(name)=[redacted]"
        }
    }

    /// Keeps scheme, host, port, path and the `deadline` parameter: enough to see which node and
    /// when the signature expires, without the signature or the account id.
    public static func url(_ text: String) -> String {
        guard let components = URLComponents(string: text), let host = components.host else {
            // Unparseable on some Foundation versions (odd characters); never pass the query through.
            return String(text.prefix { $0 != "?" && $0 != "#" })
        }
        var result = "\(components.scheme ?? "https")://\(host)"
        if let port = components.port { result += ":\(port)" }
        result += components.path
        if let deadline = components.queryItems?.first(where: { $0.name == "deadline" })?.value {
            result += "?deadline=\(deadline)"
        }
        return result
    }

    public static func mid(_ mid: Int64) -> String {
        hashed(String(mid))
    }

    private static func hashed(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "mid:" + String(String(hash, radix: 16).prefix(8))
    }

    private static func hashedID(_ value: LogValue) -> String {
        switch value {
        case .int(let number): return mid(number)
        case .string(let text):
            if text.hasPrefix("mid:") { return text }
            return Int64(text).map(mid) ?? hashed(text)
        case .double(let number): return hashed(String(number))
        case .bool(let flag): return hashed(String(flag))
        }
    }

    /// Cookie and Set-Cookie headers: names stay visible (presence matters when debugging 412s), values go.
    private static func redactCookieValues(_ header: String) -> String {
        header.split(separator: ";", omittingEmptySubsequences: false).map { segment -> String in
            let leading = segment.prefix { $0 == " " || $0 == "\t" }
            let body = segment.dropFirst(leading.count)
            if let equals = body.firstIndex(of: "=") {
                return "\(leading)\(body[..<equals])=[redacted]"
            }
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            return cookieFlags.contains(trimmed.lowercased()) || trimmed.isEmpty ? String(segment) : "\(leading)[redacted]"
        }.joined(separator: ";")
    }

    private static func replace(
        _ regex: NSRegularExpression, in text: String, transform: (_ match: String, _ groups: [String]) -> String
    ) -> String {
        let ns = NSString(string: text)
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (1..<max(match.numberOfRanges, 1)).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += transform(ns.substring(with: match.range), groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
