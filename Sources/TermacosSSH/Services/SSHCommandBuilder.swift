import Foundation

enum SSHCommandBuilder {
    static func shouldUseAskpass(for server: Server) -> Bool {
        let account = server.id.uuidString
        let hasKey = server.keyPath?.isEmpty == false
        let hasPassword = KeychainService.hasPassword(account: account)
        let hasKeyPassphrase = KeychainService.hasKeyPassphrase(account: account)

        if hasKey {
            return server.authenticationMode == .keyAndPassword
                ? hasKeyPassphrase && hasPassword
                : hasKeyPassphrase
        }
        return hasPassword
    }

    static func authenticationArguments(for server: Server, includeAutomaticIdentity: Bool = false) -> [String] {
        guard let keyPath = server.keyPath, !keyPath.isEmpty else { return [] }

        switch server.authenticationMode {
        case .automatic:
            guard includeAutomaticIdentity else { return [] }
            return ["-i", keyPath]
        case .keyOnly:
            return [
                "-i", keyPath,
                "-o", "IdentitiesOnly=yes",
                "-o", "PubkeyAuthentication=yes",
                "-o", "PasswordAuthentication=no",
                "-o", "KbdInteractiveAuthentication=no"
            ]
        case .keyAndPassword:
            return [
                "-i", keyPath,
                "-o", "IdentitiesOnly=yes",
                "-o", "PubkeyAuthentication=yes",
                "-o", "PasswordAuthentication=yes",
                "-o", "KbdInteractiveAuthentication=yes",
                "-o", "PreferredAuthentications=publickey,password,keyboard-interactive"
            ]
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func shellArguments(_ arguments: [String]) -> String {
        arguments.map(shellQuote).joined(separator: " ")
    }
}
