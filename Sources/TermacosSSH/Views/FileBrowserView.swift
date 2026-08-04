import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Custom drag payload identifier used to move a *remote* entry reference
/// between the two panes without needing its bytes on the local machine —
/// the local pane resolves it back to an SFTPEntry and triggers a real
/// download only once it lands.
private let remoteEntryDragType = "com.tebusco.termacos.sftp-entry"

struct FileBrowserView: View {
    let server: Server
    @StateObject private var session: SFTPSession
    @StateObject private var localBrowser = LocalFileBrowser()
    @State private var remoteSelection: Set<SFTPEntry.ID> = []
    @State private var localSelection: Set<LocalFileEntry.ID> = []
    @State private var showingNewFolderPrompt = false
    @State private var newFolderName = ""
    @State private var isLocalDropTargeted = false

    init(server: Server) {
        self.server = server
        _session = StateObject(wrappedValue: SFTPSession(server: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            transferBar
            Divider()
            HSplitView {
                localPane
                    .frame(minWidth: 260)
                remotePane
                    .frame(minWidth: 320)
            }
            if let transfer = session.transferInProgress {
                Divider()
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(transfer).font(.caption)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(.bar)
            }
            if let error = session.errorMessage {
                Divider()
                HStack(spacing: Theme.Spacing.sm) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                    Spacer()
                    Button {
                        session.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .task { await session.connect() }
        .onDisappear { session.disconnect() }
        .alert("Nueva carpeta", isPresented: $showingNewFolderPrompt) {
            TextField("Nombre", text: $newFolderName)
            Button("Cancelar", role: .cancel) { newFolderName = "" }
            Button("Crear") {
                let name = newFolderName
                newFolderName = ""
                Task { await session.makeDirectory(name: name) }
            }
        }
    }

    // MARK: - Transfer bar

    private var transferBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                downloadSelected()
            } label: {
                Label("Descargar", systemImage: "arrow.left.square.fill")
            }
            .disabled(remoteSelection.isEmpty || session.isLoading)
            .help("Descargar lo seleccionado a la carpeta actual de la izquierda")

            Button {
                uploadSelected()
            } label: {
                Label("Subir", systemImage: "arrow.right.square.fill")
            }
            .disabled(localSelection.isEmpty || session.isLoading)
            .help("Subir lo seleccionado a la carpeta actual del servidor")

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.bar)
    }

    private func downloadSelected() {
        let entries = session.entries.filter { remoteSelection.contains($0.id) }
        Task {
            for entry in entries {
                let localPath = localBrowser.currentURL.appendingPathComponent(entry.name).path
                await session.download(entry, to: localPath)
            }
            localBrowser.refresh()
        }
    }

    private func uploadSelected() {
        let entries = localBrowser.entries.filter { localSelection.contains($0.id) }
        Task {
            for entry in entries {
                await session.upload(localPath: entry.url.path, remoteName: entry.name, isDirectory: entry.isDirectory)
            }
        }
    }

    // MARK: - Local pane ("Este Mac")

    private var localPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Button { localBrowser.goUp() } label: { Image(systemName: "chevron.up") }
                    .disabled(!localBrowser.canGoUp)
                    .help("Subir un nivel")
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(.secondary)
                Text(localBrowser.currentURL.path)
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button { localBrowser.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Actualizar")
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.bar)
            Divider()

            List(localBrowser.entries, selection: $localSelection) { entry in
                LocalFileRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if entry.isDirectory { localBrowser.enter(entry) }
                    }
                    .onDrag {
                        NSItemProvider(contentsOf: entry.url) ?? NSItemProvider()
                    }
            }
            .listStyle(.inset)
            .overlay(
                Rectangle()
                    .strokeBorder(isLocalDropTargeted ? Theme.accent : Color.clear, lineWidth: 2)
            )
            .onDrop(of: [remoteEntryDragType], isTargeted: $isLocalDropTargeted) { providers in
                handleRemoteEntryDrop(providers)
                return true
            }
        }
    }

    private func handleRemoteEntryDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: remoteEntryDragType) { data, _ in
                guard let data = data as? Data, let name = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    guard let entry = session.entries.first(where: { $0.name == name }) else { return }
                    let localPath = localBrowser.currentURL.appendingPathComponent(entry.name).path
                    await session.download(entry, to: localPath)
                    localBrowser.refresh()
                }
            }
        }
    }

    // MARK: - Remote pane (server)

    private var remotePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Button { Task { await session.goUp() } } label: { Image(systemName: "chevron.up") }
                    .disabled(session.currentPath == "/" || session.isLoading)
                    .help("Subir un nivel")
                Image(systemName: "server.rack")
                    .foregroundStyle(Theme.accent)
                Text(session.currentPath)
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(session.isLoading)
                    .help("Actualizar")
                Button { showingNewFolderPrompt = true } label: { Image(systemName: "folder.badge.plus") }
                    .disabled(session.isLoading)
                    .help("Nueva carpeta")
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.bar)
            Divider()

            remoteContent
        }
    }

    @ViewBuilder
    private var remoteContent: some View {
        if !session.isConnected && session.isLoading {
            VStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                Text("Conectando por SFTP…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !session.isConnected {
            ContentUnavailableView(
                "Sin conexión",
                systemImage: "externaldrive.badge.xmark",
                description: Text("No se pudo establecer la sesión SFTP con este servidor.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.entries.isEmpty && !session.isLoading {
            ContentUnavailableView(
                "Carpeta vacía",
                systemImage: "folder",
                description: Text("Arrastrá archivos desde la izquierda para subirlos.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleUploadDrop(providers)
                return true
            }
        } else {
            List(session.entries, selection: $remoteSelection) { entry in
                RemoteFileRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard !session.isLoading else { return }
                        if entry.isDirectory {
                            Task { await session.enter(entry) }
                        } else {
                            Task {
                                let localPath = localBrowser.currentURL.appendingPathComponent(entry.name).path
                                await session.download(entry, to: localPath)
                                localBrowser.refresh()
                            }
                        }
                    }
                    .onDrag {
                        NSItemProvider(item: Data(entry.name.utf8) as NSData, typeIdentifier: remoteEntryDragType)
                    }
                    .contextMenu {
                        Button(entry.isDirectory ? "Descargar carpeta a \"\(localBrowser.currentURL.lastPathComponent)\"" : "Descargar a \"\(localBrowser.currentURL.lastPathComponent)\"") {
                            let localPath = localBrowser.currentURL.appendingPathComponent(entry.name).path
                            Task {
                                await session.download(entry, to: localPath)
                                localBrowser.refresh()
                            }
                        }
                        if entry.isDirectory {
                            Button("Abrir") { Task { await session.enter(entry) } }
                        }
                        Button("Eliminar", role: .destructive) {
                            Task { await session.delete(entry) }
                        }
                    }
            }
            .listStyle(.inset)
            .opacity(session.isLoading ? 0.5 : 1)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleUploadDrop(providers)
                return true
            }
        }
    }

    private func handleUploadDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                Task { @MainActor in
                    await session.upload(localPath: url.path, remoteName: url.lastPathComponent, isDirectory: isDir.boolValue)
                }
            }
        }
    }
}

private struct LocalFileRow: View {
    let entry: LocalFileEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? Theme.accent : .secondary)
                .frame(width: 16)
            Text(entry.name)
                .lineLimit(1)
            Spacer()
            if !entry.isDirectory {
                Text(FileBrowserFormatters.byteFormatter.string(fromByteCount: entry.size))
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RemoteFileRow: View {
    let entry: SFTPEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? Theme.accent : .secondary)
                .frame(width: 16)
            Text(entry.name)
                .lineLimit(1)
            if entry.isSymlink {
                Image(systemName: "arrow.turn.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !entry.isDirectory {
                Text(FileBrowserFormatters.byteFormatter.string(fromByteCount: entry.size))
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private enum FileBrowserFormatters {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
