import Foundation

enum KeyImportError: LocalizedError {
    case sourceUnreadable
    case destinationExists

    var errorDescription: String? {
        switch self {
        case .sourceUnreadable: return "No se pudo leer el archivo seleccionado."
        case .destinationExists: return "Ya existe una clave con ese nombre en ~/.ssh."
        }
    }
}

enum KeyImporter {
    /// Moves a private key the user picked via NSOpenPanel into ~/.ssh with 600
    /// permissions and returns the final path to store on the Server model.
    /// The original file is removed from its (often unprotected) source location.
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

        try fm.moveItem(at: sourceURL, to: destination)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        return destination.path
    }
}
