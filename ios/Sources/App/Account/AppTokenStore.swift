import Foundation
import Security
import DevLog

/// The app-API access token that 不喜欢 needs (spec 4.14). It sits beside the cookies, is cleared on logout, and is
/// never logged.
enum AppTokenStore {
    private static let service = "com.kaichuan.bilinative.apptoken"
    private static let account = "bilibili"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.shared.warn(.app, "app token load failed", ["status": .init(Int(status))])
        }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        guard !token.isEmpty else {
            delete()
            return true
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = baseQuery.merging(attributes) { $1 }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Logger.shared.warn(.app, "app token save failed", ["status": .init(Int(status))])
        }
        return status == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
