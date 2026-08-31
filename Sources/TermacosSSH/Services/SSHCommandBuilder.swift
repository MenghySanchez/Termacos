import Foundation

enum SSHCommandBuilder {
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
