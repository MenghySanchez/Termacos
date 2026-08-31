import Foundation
import Security

/// Stores per-server SSH passwords in the macOS Keychain, scoped by the
/// server's UUID. The app never keeps a password in memory longer than a
/// single form session, and never writes it to servers.json.
enum KeychainService {
    private static let service = "com.menghysanchez.termacos-ssh.password"
    private static let legacyService = "ec.com.tebusco.termacos-ssh.password"

    static func save(password: String, account: String) {
        delete(account: account)

        var attributes = query(service: service, account: account)
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func readPassword(account: String) -> String? {
        readPassword(service: service, account: account) ?? readPassword(service: legacyService, account: account)
    }

    static func hasPassword(account: String) -> Bool {
        hasPassword(service: service, account: account) || hasPassword(service: legacyService, account: account)
    }

    static func delete(account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
        SecItemDelete(query(service: legacyService, account: account) as CFDictionary)
    }

    private static func readPassword(service: String, account: String) -> String? {
        var query = query(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func hasPassword(service: String, account: String) -> Bool {
        var query = query(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
