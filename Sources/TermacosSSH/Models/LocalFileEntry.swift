import Foundation

struct LocalFileEntry: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?
    let url: URL
}
