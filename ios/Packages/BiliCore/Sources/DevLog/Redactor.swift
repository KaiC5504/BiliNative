import Foundation

public enum Redactor {
    static let secretNames: Set<String> = [
        "sessdata", "bili_jct", "csrf", "cookie", "set-cookie", "authorization", "access_key", "refresh_token", "dedeuserid__ckmd5",
    ]
    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s"'<>]+"#)
    private static let pairPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(SESSDATA|bili_jct|csrf|access_key|refresh_token|DedeUserID__ckMd5)=([^;&\s"]+)"#)

    public static func fields(_ fields: [String: LogValue]) -> [String: LogValue] {
        var result: [String: LogValue] = [:]
        for (key, value) in fields {
            if secretNames.contains(key.lowercased()) {
                result[key] = .string("[redacted]")
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
        let shortened = replace(urlPattern, in: input) { url($0) }
        return replace(pairPattern, in: shortened) { match in
            let name = match.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "secret"
            return "\(name)=[redacted]"
        }
    }

    /// Keeps scheme, host, port, path and the `deadline` parameter: enough to see which node and
    /// when the signature expires, without the signature or the account id.
    public static func url(_ text: String) -> String {
        guard let components = URLComponents(string: text), let host = components.host else { return text }
        var result = "\(components.scheme ?? "https")://\(host)"
        if let port = components.port { result += ":\(port)" }
        result += components.path
        if let deadline = components.queryItems?.first(where: { $0.name == "deadline" })?.value {
            result += "?deadline=\(deadline)"
        }
        return result
    }

    public static func mid(_ mid: Int64) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in String(mid).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "mid:" + String(String(hash, radix: 16).prefix(8))
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, transform: (String) -> String) -> String {
        let ns = NSString(string: text)
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(ns.substring(with: match.range))
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
