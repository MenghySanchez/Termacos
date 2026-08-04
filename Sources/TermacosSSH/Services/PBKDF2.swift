import Foundation
import CryptoKit

/// Minimal PBKDF2-HMAC-SHA256 implementation used to turn a user passphrase
/// into an AES-256 key for backup export/import. CryptoKit doesn't expose
/// PBKDF2 directly and CommonCrypto isn't importable from a plain SwiftPM
/// target, so this stretches the passphrase by hand using CryptoKit's HMAC.
enum PBKDF2 {
    static func deriveKey(passphrase: String, salt: Data, iterations: Int = 120_000) -> SymmetricKey {
        let password = SymmetricKey(data: Data(passphrase.utf8))
        let hLen = SHA256.Digest.byteCount // 32

        var blockIndexBE = UInt32(1).bigEndian
        let indexData = Data(bytes: &blockIndexBE, count: 4)

        var u = Data(HMAC<SHA256>.authenticationCode(for: salt + indexData, using: password))
        var block = u

        if iterations > 1 {
            for _ in 2...iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: password))
                for i in 0..<hLen {
                    block[i] ^= u[i]
                }
            }
        }

        return SymmetricKey(data: block)
    }
}
