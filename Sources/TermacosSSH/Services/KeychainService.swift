import Foundation
import Security

/// Stores per-server SSH secrets in the macOS Keychain, scoped by the server's
/// UUID. Secrets are never written to servers.json or app logs.
enum KeychainService {
    private static let passwordService = "com.menghysanchez.termacos-ssh.password"
    private static let keyPassphraseService = "com.menghysanchez.termacos-ssh.key-passphrase"
    private static let legacyPasswordService = "ec.com.tebusco.termacos-ssh.password"

    static func save(password: String, account: String) {
        save(secret: password, service: passwordService, account: account)
    }

    static func saveKeyPassphrase(_ passphrase: String, account: String) {
        save(secret: passphrase, service: keyPassphraseService, account: account)
    }

    private static func save(secret: String, service: String, account: String) {
        delete(service: service, account: account)

        var attributes = query(service: service, account: account)
        attributes[kSecValueData as String] = Data(secret.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func readPassword(account: String) -> String? {
        readSecret(service: passwordService, account: account) ?? readSecret(service: legacyPasswordService, account: account)
    }

    static func readKeyPassphrase(account: String) -> String? {
        readSecret(service: keyPassphraseService, account: account)
    }

    static func readAskpassSecret(account: String, prompt: String) -> String? {
        if prompt.localizedCaseInsensitiveContains("passphrase") {
            return readKeyPassphrase(account: account)
        }
        return readPassword(account: account)
    }

    static func hasPassword(account: String) -> Bool {
        hasSecret(service: passwordService, account: account) || hasSecret(service: legacyPasswordService, account: account)
    }

    static func hasKeyPassphrase(account: String) -> Bool {
        hasSecret(service: keyPassphraseService, account: account)
    }

    static func hasAskpassSecret(account: String) -> Bool {
        hasPassword(account: account) || hasKeyPassphrase(account: account)
    }

    static func delete(account: String) {
        deletePassword(account: account)
    }

    static func deletePassword(account: String) {
        delete(service: passwordService, account: account)
        delete(service: legacyPasswordService, account: account)
    }

    static func deleteKeyPassphrase(account: String) {
        delete(service: keyPassphraseService, account: account)
    }

    static func deleteAll(account: String) {
        deletePassword(account: account)
        deleteKeyPassphrase(account: account)
    }

    private static func readSecret(service: String, account: String) -> String? {
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

    private static func hasSecret(service: String, account: String) -> Bool {
        var query = query(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(service: String, account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }

    private static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
