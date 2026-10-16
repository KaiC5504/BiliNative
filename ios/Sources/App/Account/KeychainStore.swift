import Foundation
import Security
import DevLog

/// The bilibili.com cookies, as one JSON blob in a generic-password item.
enum KeychainStore {
    enum LoadResult {
        case cookies([String: String])
        case notFound
        /// The Keychain refused, e.g. errSecInteractionNotAllowed before the first unlock. The stored
        /// cookies may still be there, so callers must not overwrite them.
        case failed(OSStatus)
    }

    private static let service = "com.kaichuan.bilinative.cookies"
    private static let account = "bilibili"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> LoadResult {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .notFound }
        guard status == errSecSuccess else {
            Logger.shared.warn(.app, "keychain load failed", ["status": .init(Int(status))])
            return .failed(status)
        }
        guard let data = result as? Data,
              let cookies = try? JSONDecoder().decode([String: String].self, from: data) else {
            Logger.shared.warn(.app, "keychain item unreadable", ["status": .init(Int(errSecDecode))])
            return .failed(errSecDecode)
        }
        return .cookies(cookies)
    }

    static func loadCookies() -> [String: String] {
        if case .cookies(let cookies) = load() { return cookies }
        return [:]
    }

    @discardableResult
    static func saveCookies(_ cookies: [String: String]) -> Bool {
        if cookies.isEmpty {
            deleteCookies()
            return true
        }
        guard let data = try? JSONEncoder().encode(cookies) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = baseQuery.merging(attributes) { $1 }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Logger.shared.warn(.app, "keychain save failed", ["status": .init(Int(status))])
        }
        return status == errSecSuccess
    }

    static func deleteCookies() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
