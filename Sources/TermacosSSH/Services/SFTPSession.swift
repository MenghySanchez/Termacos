import Foundation

/// Drives the system's `/usr/bin/sftp` as an interactive subprocess over
/// plain pipes (no PTY), talking to it the way a human would at the
/// `sftp>` prompt and parsing its replies. This reuses the exact same
/// ~/.ssh/config alias, agent/Keychain key auth, and SSH_ASKPASS password
/// auth already wired up for the terminal and Terminal.app launchers —
/// no separate SSH implementation or credential path to maintain.
@MainActor
final class SFTPSession: ObservableObject {
    @Published var entries: [SFTPEntry] = []
    @Published var currentPath: String = "."
    @Published var isLoading = false
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var transferInProgress: String?

    private let server: Server
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var outputBuffer = Data()
    private var pendingContinuation: CheckedContinuation<String, Never>?
    private let promptSuffix = "sftp> "

    init(server: Server) {
        self.server = server
    }

    func connect() async {
        guard process == nil else { return }
        isLoading = true
        errorMessage = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = [server.alias]

        if KeychainService.hasPassword(account: server.id.uuidString) {
            let scriptPath = AskpassScriptProvider.ensureScript().path
            var env = ProcessInfo.processInfo.environment
            env["SSH_ASKPASS"] = scriptPath
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["TERMACOS_SERVER_ID"] = server.id.uuidString
            process.environment = env
        }

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stdout
        self.stdinHandle = stdin.fileHandleForWriting

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.handleIncoming(data)
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTermination()
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            errorMessage = "No se pudo iniciar sftp: \(error.localizedDescription)"
            isLoading = false
            return
        }

        let banner = await waitForPrompt(timeout: 15)
        if process.isRunning {
            isConnected = true
            if banner.localizedCaseInsensitiveContains("permission denied") {
                errorMessage = "Autenticación rechazada por el servidor."
            }
            await refresh()
        } else {
            errorMessage = firstMeaningfulLine(of: banner) ?? "No se pudo conectar."
        }
        isLoading = false
    }

    func disconnect() {
        stdinHandle?.closeFile()
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        isConnected = false
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        let pwdReply = await send("pwd")
        if let path = pwdReply.firstMatch(of: #/Remote working directory:\s*(\S+)/#) {
            currentPath = String(path.1)
        }
        let listing = await send("ls -la")
        entries = Self.parse(listing: listing)
        isLoading = false
    }

    func enter(_ entry: SFTPEntry) async {
        guard entry.isDirectory else { return }
        isLoading = true
        let reply = await send("cd \"\(entry.name)\"")
        if reply.localizedCaseInsensitiveContains("not found") || reply.localizedCaseInsensitiveContains("no such") {
            errorMessage = "No se pudo abrir \"\(entry.name)\"."
            isLoading = false
            return
        }
        await refresh()
    }

    func goUp() async {
        isLoading = true
        _ = await send("cd ..")
        await refresh()
    }

    func download(_ entry: SFTPEntry, to localPath: String) async {
        transferInProgress = entry.isDirectory ? "Descargando carpeta \(entry.name)…" : "Descargando \(entry.name)…"
        let flag = entry.isDirectory ? "-r " : ""
        let reply = await send("get \(flag)\"\(entry.name)\" \"\(localPath)\"", timeout: 1800)
        transferInProgress = nil
        if let problem = Self.extractError(from: reply) {
            errorMessage = problem
        }
    }

    func upload(localPath: String, remoteName: String, isDirectory: Bool = false) async {
        transferInProgress = isDirectory ? "Subiendo carpeta \(remoteName)…" : "Subiendo \(remoteName)…"
        let flag = isDirectory ? "-r " : ""
        let reply = await send("put \(flag)\"\(localPath)\" \"\(remoteName)\"", timeout: 1800)
        transferInProgress = nil
        if let problem = Self.extractError(from: reply) {
            errorMessage = problem
        }
        await refresh()
    }

    func makeDirectory(name: String) async {
        _ = await send("mkdir \"\(name)\"")
        await refresh()
    }

    func delete(_ entry: SFTPEntry) async {
        let command = entry.isDirectory ? "rmdir \"\(entry.name)\"" : "rm \"\(entry.name)\""
        let reply = await send(command)
        if let problem = Self.extractError(from: reply) {
            errorMessage = problem
        }
        await refresh()
    }

    // MARK: - Process I/O

    private func handleIncoming(_ data: Data) {
        outputBuffer.append(data)
        guard let text = String(data: outputBuffer, encoding: .utf8) else { return }
        if text.hasSuffix(promptSuffix) {
            outputBuffer.removeAll()
            pendingContinuation?.resume(returning: text)
            pendingContinuation = nil
        }
    }

    private func handleTermination() {
        isConnected = false
        if let text = String(data: outputBuffer, encoding: .utf8) {
            pendingContinuation?.resume(returning: text)
        } else {
            pendingContinuation?.resume(returning: "")
        }
        pendingContinuation = nil
    }

    @discardableResult
    private func send(_ command: String, timeout: TimeInterval = 30) async -> String {
        guard let stdinHandle, let process, process.isRunning else { return "" }
        stdinHandle.write((command + "\n").data(using: .utf8) ?? Data())
        return await waitForPrompt(timeout: timeout)
    }

    private func waitForPrompt(timeout: TimeInterval) async -> String {
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.timeoutIfStillPending()
            }
        }
    }

    private func timeoutIfStillPending() {
        guard pendingContinuation != nil else { return }
        outputBuffer.removeAll()
        pendingContinuation?.resume(returning: "")
        pendingContinuation = nil
    }

    // MARK: - Parsing

    private static func parse(listing: String) -> [SFTPEntry] {
        listing
            .split(separator: "\n")
            .compactMap { line -> SFTPEntry? in
                let raw = String(line)
                guard let match = raw.firstMatch(of: #/^([\-dl])[rwxstST\-]{9}\+?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w+\s+\d+\s+[\d:]+)\s+(.+)$/#) else {
                    return nil
                }
                let typeChar = String(match.1)
                var name = String(match.4)
                if typeChar == "l", let arrowRange = name.range(of: " -> ") {
                    name = String(name[name.startIndex..<arrowRange.lowerBound])
                }
                guard name != ".", name != ".." else { return nil }
                return SFTPEntry(
                    name: name,
                    isDirectory: typeChar == "d",
                    isSymlink: typeChar == "l",
                    size: Int64(match.2) ?? 0,
                    modified: String(match.3),
                    permissions: raw.prefix(10).description
                )
            }
            .sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func extractError(from reply: String) -> String? {
        let markers = ["couldn't", "no such", "permission denied", "not a directory", "failure"]
        for line in reply.split(separator: "\n") {
            let lower = line.lowercased()
            if markers.contains(where: lower.contains) {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func firstMeaningfulLine(of text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0 != promptSuffix.trimmingCharacters(in: .whitespaces) }
    }
}
