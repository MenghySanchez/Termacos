import Foundation
import Combine

@MainActor
final class ServerStore: ObservableObject {
    @Published var servers: [Server] = [] {
        didSet { persistAndSync() }
    }
    @Published var lastError: String?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Termacos", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("servers.json")

        load()
        ensureTeBuscoTestServer()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else {
            return
        }
        servers = decoded
        try? SSHConfigManager.sync(servers: servers)
    }

    private func persistAndSync() {
        do {
            let data = try JSONEncoder().encode(servers)
            try data.write(to: fileURL, options: .atomic)
            try SSHConfigManager.sync(servers: servers)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func upsert(_ server: Server) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        KeychainService.deleteAll(account: server.id.uuidString)
    }

    func markConnected(_ server: Server) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index].lastConnectedAt = Date()
    }

    private func ensureTeBuscoTestServer() {
        let server = Server(
            name: "TeBusco Server",
            host: "173.231.198.46",
            port: 22,
            username: "tebusc5",
            keyPath: "/Users/Men/.ssh/tebusco_server_ed25519",
            authenticationMode: .keyOnly,
            notes: "Conectar usando la VPN de TeBusco. La passphrase de la clave no se guarda en archivos."
        )

        if !servers.contains(where: { $0.name == server.name || ($0.host == server.host && $0.username == server.username) }) {
            servers.append(server)
        }
    }
}
