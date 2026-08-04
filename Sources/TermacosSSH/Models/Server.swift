import Foundation

struct Server: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String
    var keyPath: String?
    var notes: String = ""
    var lastConnectedAt: Date?

    var alias: String {
        "termacos-" + name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
