import Foundation
import BiliShared

public final class CookieJar: @unchecked Sendable {
    private let state: Locked<[String: String]>
    /// Called with the full jar after every change (the app persists it to the Keychain).
    public var onChange: (@Sendable ([String: String]) -> Void)?

    public init(_ cookies: [String: String] = [:]) {
        state = Locked(cookies)
    }

    public var all: [String: String] { state.current }

    public func value(_ name: String) -> String? {
        state.current[name]
    }

    public func set(_ name: String, _ value: String) {
        let snapshot = state.withLock { cookies -> [String: String] in
            cookies[name] = value
            return cookies
        }
        onChange?(snapshot)
    }

    public func remove(_ name: String) {
        let snapshot = state.withLock { cookies -> [String: String] in
            cookies[name] = nil
            return cookies
        }
        onChange?(snapshot)
    }

    public func replaceAll(_ cookies: [String: String]) {
        state.withLock { $0 = cookies }
        onChange?(cookies)
    }

    public func removeAll() {
        state.withLock { $0 = [:] }
        onChange?([:])
    }

    public var headerValue: String? {
        let cookies = state.current
        guard !cookies.isEmpty else { return nil }
        func rank(_ name: String) -> Int { name.lowercased() == "sessdata" ? 0 : 1 }
        return cookies.keys.sorted { (rank($0), $0) < (rank($1), $1) }
            .map { "\($0)=\(cookies[$0] ?? "")" }
            .joined(separator: "; ")
    }

    public static func parse(header: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { result[name] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return result
    }
}
