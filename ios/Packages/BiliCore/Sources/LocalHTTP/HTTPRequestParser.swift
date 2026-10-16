import Foundation

public struct HTTPRequestHead: Equatable, Sendable {
    public let method: String
    public let target: String
    public let path: String
    /// Lowercased names.
    public let headers: [String: String]

    public init(method: String, target: String, path: String, headers: [String: String]) {
        self.method = method
        self.target = target
        self.path = path
        self.headers = headers
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    case incomplete
    case invalid
    case complete(HTTPRequestHead, headerLength: Int)
}

public enum HTTPRequestParser {
    public static let maxHeaderBytes = 16 * 1024

    public static func parse(_ bytes: [UInt8]) -> HTTPParseResult {
        guard let end = headerEnd(bytes) else { return bytes.count >= maxHeaderBytes ? .invalid : .incomplete }
        let lines = String(decoding: bytes[0..<end], as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        let target = String(requestLine[1])
        let path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return .complete(HTTPRequestHead(method: requestLine[0].uppercased(), target: target, path: path, headers: headers),
                         headerLength: end + 4)
    }

    private static func headerEnd(_ bytes: [UInt8]) -> Int? {
        let limit = min(bytes.count, maxHeaderBytes)
        guard limit >= 4 else { return nil }
        for index in 0...(limit - 4) where bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10 {
            return index
        }
        return nil
    }
}
