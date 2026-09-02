import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var lockManager: AppLockManager
    @State private var selection: Server.ID?
    @State private var searchText: String = ""
    @State private var showingForm = false
    @State private var editingServer: Server?
    @State private var pendingDeletion: Server?
    @State private var terminalSessions: [TerminalSession] = []
    @State private var activeTerminalSessionID: TerminalSession.ID?
    @State private var lastExitCodes: [Server.ID: Int32] = [:]

    private var filteredServers: [Server] {
        guard !searchText.isEmpty else { return store.servers }
        return store.servers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.host.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if store.servers.isEmpty {
                    emptySidebarState
                } else {
                    List(filteredServers, selection: $selection) { server in
                        ServerRow(server: server)
                            .tag(server.id)
                            .contextMenu {
                                Button {
                                    editingServer = server
                                    showingForm = true
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    pendingDeletion = server
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Servidores")
            .searchable(text: $searchText, prompt: "Buscar servidor")
            .toolbar {
                ToolbarItem {
                    Button {
                        editingServer = nil
                        showingForm = true
                    } label: {
                        Label("Agregar servidor", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Agregar servidor (⌘N)")
                }
                ToolbarItem {
                    Button {
                        lockManager.lock()
                    } label: {
                        Label("Bloquear", systemImage: "lock.fill")
                    }
                    .keyboardShortcut("l", modifiers: .command)
                    .help("Bloquear Termacos SSH (⌘L) — corta cualquier sesión abierta")
                }
            }
        } detail: {
            detailWorkspace
        }
        .sheet(isPresented: $showingForm) {
            ServerFormView(server: editingServer) { server in
                store.upsert(server)
                withAnimation(.easeInOut(duration: 0.2)) {
                    selection = server.id
                }
            }
        }
        .alert("Error", isPresented: .constant(store.lastError != nil)) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .alert(
            "¿Eliminar \(pendingDeletion?.name ?? "")?",
            isPresented: .constant(pendingDeletion != nil),
            presenting: pendingDeletion
        ) { server in
            Button("Cancelar", role: .cancel) { pendingDeletion = nil }
            Button("Eliminar", role: .destructive) {
                store.delete(server)
                pendingDeletion = nil
            }
        } message: { server in
            Text("Se quitará \"\(server.name)\" de la lista y su entrada de ~/.ssh/config. La clave privada en ~/.ssh no se borra.")
        }
    }

    @ViewBuilder
    private var detailWorkspace: some View {
        if terminalSessions.isEmpty {
            selectedServerDetail
        } else {
            VSplitView {
                selectedServerDetail
                    .frame(minHeight: 220)
                TerminalSessionsView(
                    sessions: terminalSessions,
                    activeSessionID: $activeTerminalSessionID,
                    onExit: recordTerminalExit,
                    onClose: closeTerminalSession
                )
                .frame(minHeight: 260)
            }
        }
    }

    @ViewBuilder
    private var selectedServerDetail: some View {
        if let server = store.servers.first(where: { $0.id == selection }) {
            ServerDetailView(
                server: server,
                lastExitCode: lastExitCodes[server.id],
                onEdit: {
                    editingServer = server
                    showingForm = true
                },
                onConnect: openTerminalSession
            )
            .id(server.id)
        } else {
            ContentUnavailableView(
                "Sin servidor seleccionado",
                systemImage: "server.rack",
                description: Text("Elegí un servidor de la lista o agregá uno nuevo.")
            )
        }
    }

    private func openTerminalSession(for server: Server) {
        if let session = terminalSessions.first(where: { $0.server.id == server.id && $0.exitCode == nil }) {
            activeTerminalSessionID = session.id
            return
        }

        terminalSessions.removeAll { $0.server.id == server.id && $0.exitCode != nil }
        lastExitCodes[server.id] = nil
        store.markConnected(server)

        let session = TerminalSession(server: server)
        terminalSessions.append(session)
        activeTerminalSessionID = session.id
    }

    private func recordTerminalExit(sessionID: TerminalSession.ID, server: Server, exitCode: Int32?) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        terminalSessions[index].exitCode = exitCode
        if let exitCode {
            lastExitCodes[server.id] = exitCode
        }
    }

    private func closeTerminalSession(_ sessionID: TerminalSession.ID) {
        let wasActive = activeTerminalSessionID == sessionID
        terminalSessions.removeAll { $0.id == sessionID }
        guard wasActive else { return }
        activeTerminalSessionID = terminalSessions.last?.id
    }

    private var emptySidebarState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "server.rack")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Sin servidores")
                .font(.headline)
            Text("Agregá tu primer servidor para empezar a conectarte.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                editingServer = nil
                showingForm = true
            } label: {
                Label("Agregar servidor", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalSession: Identifiable, Equatable {
    let id = UUID()
    let server: Server
    var exitCode: Int32?
}

private struct ServerRow: View {
    let server: Server

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accent.opacity(0.16))
                Image(systemName: "server.rack")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(.body, weight: .medium))
                Text("\(server.username)@\(server.host)")
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ServerDetailView: View {
    let server: Server
    let lastExitCode: Int32?
    let onEdit: () -> Void
    let onConnect: (Server) -> Void

    @AppStorage("defaultTerminalApp") private var defaultTerminalAppRaw: String = TerminalApp.terminal.rawValue
    @State private var mode: DetailMode = .overview
    @State private var copiedField: String?

    private enum DetailMode: Equatable {
        case overview, files
    }

    private var defaultTerminalApp: TerminalApp {
        TerminalApp(rawValue: defaultTerminalAppRaw) ?? .terminal
    }

    private var connectionString: String {
        "\(server.username)@\(server.host):\(server.port)"
    }

    var body: some View {
        Group {
            switch mode {
            case .overview:
                overview
            case .files:
                fileBrowserSession
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private var fileBrowserSession: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Theme.accent)
                Text("\(server.name) — Archivos")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Cerrar") { mode = .overview }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.bar)
            Divider()
            FileBrowserView(server: server)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(server.name)
                        .font(.largeTitle.bold())
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(connectionString)
                            .font(.mono(14))
                            .foregroundStyle(.secondary)
                        CopyButton(value: connectionString, fieldID: "connection", copiedField: $copiedField)
                    }
                    if let lastConnectedAt = server.lastConnectedAt {
                        Text("Última conexión \(lastConnectedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Label("Editar", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let keyPath = server.keyPath, !keyPath.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        Label(keyPath, systemImage: "key.fill")
                            .font(.mono(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        CopyButton(value: keyPath, fieldID: "key", copiedField: $copiedField)
                    }
                } else {
                    Label("Sin clave asociada (se usará el agente SSH)", systemImage: "key.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !server.notes.isEmpty {
                    Text(server.notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastExitCode, let reason = SSHExitCode.description(for: lastExitCode, server: server) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.warning)
            }

            Divider()

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    onConnect(server)
                } label: {
                    Label("Conectar en pestaña", systemImage: "terminal.fill")
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    mode = .files
                } label: {
                    Label("Archivos", systemImage: "folder")
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Menu {
                    ForEach(TerminalApp.allCases.filter(\.isInstalled)) { app in
                        Button("Abrir en \(app.displayName)") {
                            defaultTerminalAppRaw = app.rawValue
                            TerminalLauncher.connect(server: server, using: app)
                        }
                    }
                } label: {
                    Label("Abrir externamente", systemImage: "arrow.up.forward.app")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TerminalSessionsView: View {
    let sessions: [TerminalSession]
    @Binding var activeSessionID: TerminalSession.ID?
    let onExit: (TerminalSession.ID, Server, Int32?) -> Void
    let onClose: (TerminalSession.ID) -> Void

    private var selectedSessionID: TerminalSession.ID? {
        activeSessionID ?? sessions.first?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ZStack {
                ForEach(sessions) { session in
                    let isActive = session.id == selectedSessionID
                    TerminalSessionPane(
                        session: session,
                        isActive: isActive,
                        onExit: onExit
                    )
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
                    .zIndex(isActive ? 1 : 0)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(sessions) { session in
                    let isActive = session.id == selectedSessionID
                    HStack(spacing: 0) {
                        Button {
                            activeSessionID = session.id
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Circle()
                                    .fill(session.exitCode == nil ? Theme.accent : Theme.warning)
                                    .frame(width: 7, height: 7)
                                Text(session.server.name)
                                    .font(.callout.weight(isActive ? .semibold : .regular))
                                    .lineLimit(1)
                                if session.exitCode != nil {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.warning)
                                }
                            }
                            .padding(.leading, Theme.Spacing.sm)
                            .padding(.trailing, Theme.Spacing.xs)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onClose(session.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .help("Cerrar sesión")
                    }
                    .background(
                        isActive ? Theme.accent.opacity(0.16) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(.bar)
    }
}

private struct TerminalSessionPane: View {
    let session: TerminalSession
    let isActive: Bool
    let onExit: (TerminalSession.ID, Server, Int32?) -> Void

    private var connectionString: String {
        "\(session.server.username)@\(session.server.host):\(session.server.port)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: session.exitCode == nil ? "terminal.fill" : "terminal")
                    .foregroundStyle(session.exitCode == nil ? Theme.accent : Theme.warning)
                Text(connectionString)
                    .font(.mono(12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let exitCode = session.exitCode, let reason = SSHExitCode.description(for: exitCode, server: session.server) {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                } else {
                    Text("Sesión activa")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.bar)
            Divider()
            EmbeddedTerminalView(server: session.server, isActive: isActive) { exitCode in
                onExit(session.id, session.server, exitCode)
            }
        }
    }
}

private struct CopyButton: View {
    let value: String
    let fieldID: String
    @Binding var copiedField: String?

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            copiedField = fieldID
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedField == fieldID { copiedField = nil }
            }
        } label: {
            Image(systemName: copiedField == fieldID ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copiedField == fieldID ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copiar")
        .animation(.easeInOut(duration: 0.15), value: copiedField)
    }
}
