import Foundation

/// Browses the local filesystem the same way SFTPSession browses the
/// remote one, so the two panes share the same navigation model. Purely
/// synchronous — FileManager directory reads are cheap and local.
@MainActor
final class LocalFileBrowser: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var entries: [LocalFileEntry] = []

    init(startURL: URL? = nil) {
        currentURL = startURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let contents = (try? fm.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        entries = contents.compactMap { url -> LocalFileEntry? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return LocalFileEntry(
                name: url.lastPathComponent,
                isDirectory: values.isDirectory ?? false,
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate,
                url: url
            )
        }
        .sorted {
            $0.isDirectory != $1.isDirectory
                ? $0.isDirectory
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func enter(_ entry: LocalFileEntry) {
        guard entry.isDirectory else { return }
        currentURL = entry.url
        refresh()
    }

    func goUp() {
        guard currentURL.pathComponents.count > 1 else { return }
        currentURL = currentURL.deletingLastPathComponent()
        refresh()
    }

    var canGoUp: Bool {
        currentURL.pathComponents.count > 1
    }
}
