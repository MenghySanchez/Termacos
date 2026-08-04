import Foundation

/// Writes a clearly delimited, auto-generated block into ~/.ssh/config so the
/// app never touches any Host entries the user manages by hand.
enum SSHConfigManager {
    private static let beginMarker = "# >>> Termacos SSH Manager (auto-generated, do not edit) >>>"
    private static let endMarker = "# <<< Termacos SSH Manager <<<"

    static var sshDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    }

    static var configURL: URL {
        sshDirectory.appendingPathComponent("config")
    }

    static func ensureSSHDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sshDirectory.path) {
            try fm.createDirectory(at: sshDirectory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
    }

    static func sync(servers: [Server]) throws {
        try ensureSSHDirectory()

        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let outside = stripManagedBlock(from: existing)

        var block = beginMarker + "\n"
        for server in servers {
            block += "Host \(server.alias)\n"
            block += "    HostName \(server.host)\n"
            block += "    User \(server.username)\n"
            block += "    Port \(server.port)\n"
            if let keyPath = server.keyPath, !keyPath.isEmpty {
                block += "    IdentityFile \(keyPath)\n"
                block += "    IdentitiesOnly yes\n"
            }
            block += "    UseKeychain yes\n"
            block += "    AddKeysToAgent yes\n"
            block += "\n"
        }
        block += endMarker + "\n"

        let newContents: String
        if outside.isEmpty {
            newContents = block
        } else {
            newContents = outside.trimmingCharacters(in: .newlines) + "\n\n" + block
        }

        try newContents.write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private static func stripManagedBlock(from contents: String) -> String {
        guard let beginRange = contents.range(of: beginMarker),
              let endRange = contents.range(of: endMarker) else {
            return contents
        }
        var result = contents
        result.removeSubrange(beginRange.lowerBound..<endRange.upperBound)
        return result
    }
}
