import Foundation
import Security

/// Minimal Keychain wrapper for the optional custom lock code. Stored with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so it never syncs via
/// iCloud Keychain and never rides along with the CloudKit-synced journal
/// store (build spec §12).
enum KeychainStore {
    private static let service = "com.mystorydailyjournal.applock"
    private static let account = "customCode"

    static func saveCode(_ code: String) {
        guard let data = code.data(using: .utf8) else { return }
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadCode() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteCode() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
