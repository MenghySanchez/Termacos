import SwiftUI
import AppKit

struct ServerFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var keyPath: String
    @State private var authenticationMode: ServerAuthenticationMode
    @State private var notes: String
    @State private var importError: String?
    @State private var password: String = ""
    @State private var hasSavedPassword: Bool
    @State private var isTestingConnection = false
    @State private var testResult: SSHConnectionTestOutcome?

    private let originalID: UUID
    private let onSave: (Server) -> Void

    init(server: Server?, onSave: @escaping (Server) -> Void) {
        let id = server?.id ?? UUID()
        self.originalID = id
        self.onSave = onSave
        _name = State(initialValue: server?.name ?? "")
        _host = State(initialValue: server?.host ?? "")
        _port = State(initialValue: String(server?.port ?? 22))
        _username = State(initialValue: server?.username ?? "")
        _keyPath = State(initialValue: server?.keyPath ?? "")
        _authenticationMode = State(initialValue: server?.authenticationMode ?? .automatic)
        _notes = State(initialValue: server?.notes ?? "")
        _hasSavedPassword = State(initialValue: KeychainService.hasPassword(account: id.uuidString))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(port) != nil
    }

    private var canTestConnection: Bool {
        isValid &&
        !isTestingConnection &&
        (!authenticationMode.requiresKey || !keyPath.isEmpty) &&
        (authenticationMode != .keyAndPassword || hasSavedPassword || !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Servidor") {
                    TextField("Nombre (ej. Producción)", text: $name)
                    TextField("Host o IP", text: $host)
                    TextField("Puerto", text: $port)
                    TextField("Usuario", text: $username)
                }

                Section("Clave privada") {
                    if keyPath.isEmpty {
                        Button {
                            importKey()
                        } label: {
                            Label("Importar clave privada…", systemImage: "square.and.arrow.down")
                        }
                        Text("Usá una llave privada en formato OpenSSH. Las llaves PuTTY (.ppk) deben convertirse antes de importarlas. Se moverá a ~/.ssh con permisos restringidos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Label {
                                Text(keyPath)
                                    .font(.mono(12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                            Spacer()
                            Button("Quitar", role: .destructive) { keyPath = "" }
                        }
                    }
                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Picker("Autenticación", selection: $authenticationMode) {
                        ForEach(ServerAuthenticationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(authenticationMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if authenticationMode.requiresKey && keyPath.isEmpty {
                        Text("Este modo requiere importar una llave privada.")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                }

                Section(authenticationMode == .keyAndPassword ? "Contraseña (requerida con llave)" : "Contraseña (opcional)") {
                    if hasSavedPassword {
                        HStack {
                            Label("Contraseña guardada en el Llavero", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Button("Quitar", role: .destructive) {
                                KeychainService.delete(account: originalID.uuidString)
                                hasSavedPassword = false
                            }
                        }
                    } else {
                        SecureField("Contraseña del usuario", text: $password)
                        Text(authenticationMode == .keyAndPassword ? "Se usará junto con la llave privada cuando el servidor exija ambos factores." : "Se guarda cifrada en el Llavero de macOS y se usa para autenticarte automáticamente. Dejalo vacío para que SSH te la pida cada vez.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Probar conexión") {
                    Button {
                        testConnection()
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                            Text("Probando conexión…")
                        } else {
                            Label("Probar conexión", systemImage: "network")
                        }
                    }
                    .disabled(!canTestConnection)

                    if authenticationMode.requiresKey && keyPath.isEmpty {
                        Text("Importá una llave privada antes de probar este tipo de conexión.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if authenticationMode == .keyAndPassword && password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasSavedPassword {
                        Text("Para probar llave + contraseña, ingresá la contraseña o usá una ya guardada.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let testResult {
                        Label(testResult.message, systemImage: testResult.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(testResult.succeeded ? Theme.accent : Theme.warning)
                    }
                }

                Section("Notas") {
                    TextField("Opcional", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 520, height: 650)
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.title = "Seleccioná la clave privada"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let suggested = name.isEmpty ? url.lastPathComponent : name
            let finalPath = try KeyImporter.importKey(from: url, suggestedName: suggested)
            keyPath = finalPath
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func testConnection() {
        guard canTestConnection else { return }
        isTestingConnection = true
        testResult = nil

        let server = draftServer()
        let enteredPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwordForTest = enteredPassword.isEmpty
            ? KeychainService.readPassword(account: originalID.uuidString)
            : enteredPassword

        Task {
            let result = await SSHConnectionTester.test(server: server, password: passwordForTest)
            await MainActor.run {
                testResult = result
                isTestingConnection = false
            }
        }
    }

    private func draftServer() -> Server {
        Server(
            id: originalID,
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespaces),
            keyPath: keyPath.isEmpty ? nil : keyPath,
            authenticationMode: authenticationMode,
            notes: notes
        )
    }

    private func save() {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPassword.isEmpty {
            KeychainService.save(password: trimmedPassword, account: originalID.uuidString)
        }

        onSave(draftServer())
        dismiss()
    }
}
