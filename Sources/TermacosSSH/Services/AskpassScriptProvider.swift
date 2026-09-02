import Foundation

/// Writes a tiny shell shim that re-invokes this same app binary with a
/// hidden `--termacos-askpass` flag. Using the app's own executable (instead
/// of a second helper tool) means Keychain sees the identical code signature
/// that created the item, so macOS doesn't prompt for access each time.
enum AskpassScriptProvider {
    static var scriptURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Termacos", isDirectory: true)
            .appendingPathComponent("askpass.sh")
    }

    @discardableResult
    static func ensureScript() -> URL {
        let url = scriptURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let content = """
        #!/bin/bash
        exec "\(executablePath)" --termacos-askpass "$TERMACOS_SERVER_ID" "$@"
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
