import Foundation
import AppKit

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iterm = "iTerm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}

enum TerminalLauncher {
    /// Builds the shell command that launches ssh for a server, wiring up
    /// SSH_ASKPASS so a Keychain-saved password is supplied automatically
    /// instead of ssh prompting interactively.
    static func shellCommand(for server: Server) -> String {
        let authArguments = SSHCommandBuilder.authenticationArguments(for: server)
        let sshArguments = SSHCommandBuilder.shellArguments(authArguments + [server.alias])

        guard SSHCommandBuilder.shouldUseAskpass(for: server) else {
            return "ssh \(sshArguments)"
        }
        let scriptPath = AskpassScriptProvider.ensureScript().path
        return "env SSH_ASKPASS=\(SSHCommandBuilder.shellQuote(scriptPath)) SSH_ASKPASS_REQUIRE=force TERMACOS_SERVER_ID=\(SSHCommandBuilder.shellQuote(server.id.uuidString)) ssh \(sshArguments)"
    }

    /// Opens a new Terminal/iTerm window and runs the ssh command for `server`.
    /// `server.alias` is always app-generated (letters/digits/dash only), and
    /// the askpass path/UUID above never contain user-controlled characters,
    /// so this is safe to interpolate into the AppleScript string.
    static func connect(server: Server, using app: TerminalApp) {
        let command = shellCommand(for: server)
        let script: String

        switch app {
        case .terminal:
            script = """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """
        case .iterm:
            script = """
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                end if
                tell current window
                    create tab with default profile
                    tell current session
                        write text "\(command)"
                    end tell
                end tell
            end tell
            """
        }

        var errorDict: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&errorDict)
        }
    }
}
