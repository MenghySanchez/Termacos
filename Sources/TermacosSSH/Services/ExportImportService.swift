import Foundation
import CryptoKit

enum ExportImportError: LocalizedError {
    case noServers
    case emptyPassphrase
    case passphraseMismatch
    case invalidFile
    case wrongPassphraseOrCorrupt

    var errorDescription: String? {
        switch self {
        case .noServers:
            return "No hay servidores para exportar."
        case .emptyPassphrase:
            return "Ingresá una contraseña para proteger el archivo."
        case .passphraseMismatch:
            return "Las contraseñas no coinciden."
        case .invalidFile:
            return "El archivo no es un backup válido de Termacos SSH."
        case .wrongPassphraseOrCorrupt:
            return "Contraseña incorrecta o archivo dañado."
        }
    }
}

/// Encrypts/decrypts `.termacos` backup files. Pure functions only — the
/// view layer is responsible for actually writing servers into `ServerStore`
/// and passwords into the Keychain once a file has been decoded.
enum ExportImportService {
    static let fileExtension = "termacos"
    private static let currentVersion = 1

    // MARK: Export

    static func export(
        servers: [Server],
        includeKeys: Bool,
        includePasswords: Bool,
        passphrase: String
    ) throws -> Data {
        guard !servers.isEmpty else { throw ExportImportError.noServers }
        guard !passphrase.isEmpty else { throw ExportImportError.emptyPassphrase }

        var passwords: [String: String] = [:]
        var keyFiles: [String: KeyFilePayload] = [:]
        let fm = FileManager.default

        for server in servers {
            let account = server.id.uuidString

            if includePasswords, let password = KeychainService.readPassword(account: account) {
                passwords[account] = password
            }

            if includeKeys, let keyPath = server.keyPath, !keyPath.isEmpty,
               let privateData = fm.contents(atPath: keyPath) {
                let publicData = fm.contents(atPath: keyPath + ".pub")
                keyFiles[account] = KeyFilePayload(
                    filename: (keyPath as NSString).lastPathComponent,
                    privateKeyData: privateData,
                    publicKeyData: publicData
                )
            }
        }

        let payload = ExportPayload(servers: servers, passwords: passwords, keyFiles: keyFiles)
        let plaintext = try JSONEncoder().encode(payload)

        let salt = randomBytes(16)
        let key = PBKDF2.deriveKey(passphrase: passphrase, salt: salt)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else { throw ExportImportError.invalidFile }

        let envelope = ExportEnvelope(version: currentVersion, salt: salt, sealedBox: combined)
        return try JSONEncoder().encode(envelope)
    }

    // MARK: Import

    /// Decrypts `data`, then writes any bundled private keys into `~/.ssh`
    /// (skipping identical files already there, renaming on real collisions)
    /// and returns a plan the caller applies to `ServerStore` / Keychain.
    static func prepareImport(data: Data, passphrase: String) throws -> ImportPlan {
        guard let envelope = try? JSONDecoder().decode(ExportEnvelope.self, from: data) else {
            throw ExportImportError.invalidFile
        }
        guard envelope.version <= currentVersion else {
            throw ExportImportError.invalidFile
        }

        let key = PBKDF2.deriveKey(passphrase: passphrase, salt: envelope.salt)
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.sealedBox)
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw ExportImportError.wrongPassphraseOrCorrupt
        }

        guard let payload = try? JSONDecoder().decode(ExportPayload.self, from: plaintext) else {
            throw ExportImportError.wrongPassphraseOrCorrupt
        }

        try SSHConfigManager.ensureSSHDirectory()

        var renamed: [String] = []
        var keysWritten = 0
        var resolvedServers: [Server] = []

        for var server in payload.servers {
            if let keyFile = payload.keyFiles[server.id.uuidString] {
                server.keyPath = try writeKeyFile(keyFile, renamed: &renamed)
                keysWritten += 1
            }
            resolvedServers.append(server)
        }

        return ImportPlan(
            servers: resolvedServers,
            passwordsByAccount: payload.passwords,
            keysWritten: keysWritten,
            passwordsAvailable: payload.passwords.count,
            renamedKeyFiles: renamed
        )
    }

    /// Writes a bundled key into `~/.ssh`. If a file with the same name
    /// already exists and holds identical bytes, reuses it as-is. If it
    /// exists with different content (e.g. an unrelated key on this Mac
    /// happens to share the name), picks a free suffixed name instead of
    /// overwriting it.
    private static func writeKeyFile(_ keyFile: KeyFilePayload, renamed: inout [String]) throws -> String {
        let fm = FileManager.default
        let dir = SSHConfigManager.sshDirectory
        var destination = dir.appendingPathComponent(keyFile.filename)

        if fm.fileExists(atPath: destination.path) {
            if fm.contents(atPath: destination.path) == keyFile.privateKeyData {
                return destination.path
            }
            let base = (keyFile.filename as NSString).deletingPathExtension
            let ext = (keyFile.filename as NSString).pathExtension
            var counter = 1
            repeat {
                let candidate = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
                destination = dir.appendingPathComponent(candidate)
                counter += 1
            } while fm.fileExists(atPath: destination.path)
            renamed.append(destination.lastPathComponent)
        }

        try keyFile.privateKeyData.write(to: destination, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        if let publicData = keyFile.publicKeyData {
            let pubDestination = URL(fileURLWithPath: destination.path + ".pub")
            try? publicData.write(to: pubDestination, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pubDestination.path)
        }

        return destination.path
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
