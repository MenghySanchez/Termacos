import Foundation

enum ServerAuthenticationMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic
    case keyOnly
    case keyAndPassword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automática"
        case .keyOnly:
            return "Solo llave"
        case .keyAndPassword:
            return "Requiere llave y contraseña juntas"
        }
    }

    var description: String {
        switch self {
        case .automatic:
            return "SSH usará la llave si está disponible y permitirá contraseña como respaldo."
        case .keyOnly:
            return "SSH intentará autenticar solo con la llave. Si falla, la conexión se rechazará."
        case .keyAndPassword:
            return "Para servidores que exigen primero la llave privada y luego la contraseña del usuario."
        }
    }

    var requiresKey: Bool {
        self == .keyOnly || self == .keyAndPassword
    }
}

struct Server: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String
    var keyPath: String?
    var authenticationMode: ServerAuthenticationMode = .automatic
    var notes: String = ""
    var lastConnectedAt: Date?

    var keyRequired: Bool { authenticationMode == .keyOnly }
    var requiresKeyAndPassword: Bool { authenticationMode == .keyAndPassword }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        keyPath: String? = nil,
        authenticationMode: ServerAuthenticationMode = .automatic,
        notes: String = "",
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.keyPath = keyPath
        self.authenticationMode = authenticationMode
        self.notes = notes
        self.lastConnectedAt = lastConnectedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, keyPath, keyRequired, authenticationMode, notes, lastConnectedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decode(String.self, forKey: .username)
        keyPath = try container.decodeIfPresent(String.self, forKey: .keyPath)
        if let decodedMode = try container.decodeIfPresent(ServerAuthenticationMode.self, forKey: .authenticationMode) {
            authenticationMode = decodedMode
        } else if try container.decodeIfPresent(Bool.self, forKey: .keyRequired) == true {
            authenticationMode = .keyOnly
        } else {
            authenticationMode = .automatic
        }
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(keyPath, forKey: .keyPath)
        try container.encode(authenticationMode, forKey: .authenticationMode)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(lastConnectedAt, forKey: .lastConnectedAt)
    }

    var alias: String {
        "termacos-" + name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
