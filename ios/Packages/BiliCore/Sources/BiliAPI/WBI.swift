enum WBI {
    private static let table: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ]

    static func mixinKey(imgKey: String, subKey: String) -> String {
        let raw = Array(imgKey + subKey)
        return String(table.compactMap { $0 < raw.count ? raw[$0] : nil }.prefix(32))
    }

    /// The key is the file name of the image URL Bilibili hands out in `nav`, without extension.
    static func key(fromURL url: String) -> String {
        let file = url.split(separator: "/").last.map(String.init) ?? ""
        return file.split(separator: ".").first.map(String.init) ?? ""
    }

    /// encodeURIComponent semantics: everything except A-Z a-z 0-9 - . _ ~ is percent-encoded.
    static func encodeComponent(_ text: String) -> String {
        let hexDigits = Array("0123456789ABCDEF")
        var output = ""
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F, 0x7E:
                output.append(Character(UnicodeScalar(byte)))
            default:
                output.append("%")
                output.append(hexDigits[Int(byte >> 4)])
                output.append(hexDigits[Int(byte & 0x0f)])
            }
        }
        return output
    }

    static func encodeQuery(_ params: [String: String]) -> String {
        params.keys.sorted().map { "\(encodeComponent($0))=\(encodeComponent(params[$0] ?? ""))" }.joined(separator: "&")
    }

    static func signedQuery(_ params: [String: String], mixinKey: String, wts: Int) -> String {
        var cleaned = params.mapValues { value in value.filter { !"!'()*".contains($0) } }
        cleaned["wts"] = String(wts)
        let query = encodeQuery(cleaned)
        return query + "&w_rid=" + MD5.hex(query + mixinKey)
    }
}
