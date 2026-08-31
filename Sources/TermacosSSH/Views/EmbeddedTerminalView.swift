import SwiftUI
import SwiftTerm
import AppKit

final class EmbeddedTerminalCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    var onTitleChange: ((String) -> Void)?
    var onExit: ((Int32?) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onExit?(exitCode)
    }
}

/// Embeds a real PTY running `ssh <alias>` inside the app window, using the
/// same ~/.ssh/config aliases (and Keychain-backed passphrase) the launcher
/// buttons use — no separate auth path to maintain.
struct EmbeddedTerminalView: NSViewRepresentable {
    let server: Server
    var onExit: ((Int32?) -> Void)? = nil

    func makeCoordinator() -> EmbeddedTerminalCoordinator {
        let coordinator = EmbeddedTerminalCoordinator()
        coordinator.onExit = onExit
        return coordinator
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator

        var environment = Terminal.getEnvironmentVariables()
        if KeychainService.hasPassword(account: server.id.uuidString) {
            let scriptPath = AskpassScriptProvider.ensureScript().path
            environment.append("SSH_ASKPASS=\(scriptPath)")
            environment.append("SSH_ASKPASS_REQUIRE=force")
            environment.append("TERMACOS_SERVER_ID=\(server.id.uuidString)")
        }

        var args = [server.alias]
        if server.keyRequired, let keyPath = server.keyPath, !keyPath.isEmpty {
            args = ["-i", keyPath, server.alias]
        }

        view.startProcess(executable: "/usr/bin/ssh", args: args, environment: environment)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: EmbeddedTerminalCoordinator) {
        if nsView.process.running {
            nsView.process.terminate()
        }
    }
}
