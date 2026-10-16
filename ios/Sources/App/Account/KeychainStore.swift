import Foundation
import Security

/// The bilibili.com cookies, as one JSON blob in a generic-password item.
enum KeychainStore {
    private static let service = "com.kaichuan.bilinative.cookies"
    private static let account = "bilibili"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func loadCookies() -> [String: String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let cookies = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return cookies
    }

    @discardableResult
    static func saveCookies(_ cookies: [String: String]) -> Bool {
        if cookies.isEmpty {
            deleteCookies()
            return true
        }
        guard let data = try? JSONEncoder().encode(cookies) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = baseQuery.merging(attributes) { $1 }
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func deleteCookies() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
