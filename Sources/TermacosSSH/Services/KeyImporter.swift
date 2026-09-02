import Foundation

enum KeyImportError: LocalizedError {
    case sourceUnreadable
    case destinationExists
    case publicKeySelected
    case unsupportedPrivateKeyFormat
    case puttygenMissing
    case puttyConversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnreadable: return "No se pudo leer el archivo seleccionado."
        case .destinationExists: return "Ya existe una clave con ese nombre en ~/.ssh."
        case .publicKeySelected:
            return "Seleccionaste una clave pública (.pub). Para autenticar SSH debes seleccionar la clave privada, por ejemplo el archivo sin .pub."
        case .unsupportedPrivateKeyFormat:
            return "La clave privada no tiene un formato SSH soportado. Usá una clave OpenSSH, RSA, EC o DSA privada."
        case .puttygenMissing:
            return "La llave .ppk necesita convertirse a OpenSSH. Instalá el conversor con: brew install putty. Después volvé a importar la llave y Termacos la convertirá automáticamente."
        case .puttyConversionFailed(let detail):
            return detail.isEmpty
                ? "No se pudo convertir la llave .ppk a formato OpenSSH."
                : "No se pudo convertir la llave .ppk: \(detail)"
        }
    }
}

enum KeyImporter {
    /// Validates a private key selected via NSOpenPanel and returns the path to
    /// store on the Server model. OpenSSH keys are used in place; PuTTY keys are
    /// converted to OpenSSH in ~/.ssh when puttygen is available.
    static func importKey(from sourceURL: URL, suggestedName: String) throws -> String {
        try SSHConfigManager.ensureSSHDirectory()

        let fm = FileManager.default
        let safeName = suggestedName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        var destination = SSHConfigManager.sshDirectory.appendingPathComponent("id_\(safeName)")

        var counter = 1
        while fm.fileExists(atPath: destination.path) {
            destination = SSHConfigManager.sshDirectory.appendingPathComponent("id_\(safeName)_\(counter)")
            counter += 1
        }

        guard fm.isReadableFile(atPath: sourceURL.path) else {
            throw KeyImportError.sourceUnreadable
        }

        if isPuTTYPrivateKey(sourceURL) {
            try convertPuTTYKey(from: sourceURL, to: destination)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination.path
        }

        let kind = try privateKeyKind(sourceURL)
        switch kind {
        case .privateKey:
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceURL.path)
            return sourceURL.path
        case .publicKey:
            throw KeyImportError.publicKeySelected
        case .unsupported:
            throw KeyImportError.unsupportedPrivateKeyFormat
        }
    }

    private enum KeyKind {
        case privateKey
        case publicKey
        case unsupported
    }

    private static func isPuTTYPrivateKey(_ url: URL) -> Bool {
        if url.pathExtension.localizedCaseInsensitiveCompare("ppk") == .orderedSame {
            return true
        }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data.prefix(128), encoding: .utf8) else {
            return false
        }
        return text.hasPrefix("PuTTY-User-Key-File-")
    }

    private static func privateKeyKind(_ url: URL) throws -> KeyKind {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data.prefix(4096), encoding: .utf8) else {
            throw KeyImportError.sourceUnreadable
        }

        if url.pathExtension.localizedCaseInsensitiveCompare("pub") == .orderedSame ||
            text.hasPrefix("ssh-rsa ") ||
            text.hasPrefix("ssh-ed25519 ") ||
            text.hasPrefix("ecdsa-sha2-") ||
            text.hasPrefix("sk-ssh-") ||
            text.hasPrefix("sk-ecdsa-") {
            return .publicKey
        }

        let supportedHeaders = [
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "-----BEGIN RSA PRIVATE KEY-----",
            "-----BEGIN EC PRIVATE KEY-----",
            "-----BEGIN DSA PRIVATE KEY-----",
            "-----BEGIN PRIVATE KEY-----"
        ]
        return supportedHeaders.contains(where: text.contains) ? .privateKey : .unsupported
    }

    private static func convertPuTTYKey(from sourceURL: URL, to destinationURL: URL) throws {
        guard let puttygenPath = findPuttygen() else {
            throw KeyImportError.puttygenMissing
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: puttygenPath)
        process.arguments = [sourceURL.path, "-O", "private-openssh", "-o", destinationURL.path]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw KeyImportError.puttyConversionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw KeyImportError.puttyConversionFailed(detail)
        }
    }

    private static func findPuttygen() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/puttygen",
            "/usr/local/bin/puttygen",
            "/usr/bin/puttygen"
        ]

        if let path = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return path
        }

        let pathEnvironment = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return pathEnvironment
            .split(separator: ":")
            .map { String($0) + "/puttygen" }
            .first { fm.isExecutableFile(atPath: $0) }
    }
}
