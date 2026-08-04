import Foundation

/// On-disk container for a `.termacos` backup file. The payload is always
/// AES-GCM encrypted with a key derived from a user-chosen passphrase — the
/// file routinely carries private keys and Keychain passwords, so it must
/// never be readable just by finding it on disk (USB stick, cloud drive, etc).
struct ExportEnvelope: Codable {
    var version: Int
    var salt: Data
    var sealedBox: Data
}

/// The actual backup contents, encrypted inside `ExportEnvelope.sealedBox`.
struct ExportPayload: Codable {
    var servers: [Server]
    /// Keyed by `Server.id.uuidString`. Only present for servers whose
    /// password the user chose to include.
    var passwords: [String: String]
    /// Keyed by `Server.id.uuidString`. Only present for servers whose
    /// private key the user chose to include.
    var keyFiles: [String: KeyFilePayload]
}

struct KeyFilePayload: Codable {
    var filename: String
    var privateKeyData: Data
    var publicKeyData: Data?
}

/// Result of decrypting and materializing a backup file, ready to be handed
/// to `ServerStore` and `KeychainService` by the view layer.
struct ImportPlan {
    var servers: [Server]
    var passwordsByAccount: [String: String]
    var keysWritten: Int
    var passwordsAvailable: Int
    var renamedKeyFiles: [String]

    var serversCount: Int { servers.count }
}
