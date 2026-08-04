import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "Exportar / Importar" section embedded in Settings. Lets the user bundle
/// their servers (and, opt-in, private keys / Keychain passwords) into a
/// single encrypted `.termacos` file to move to another Mac running the app.
struct ExportImportSection: View {
    @EnvironmentObject private var store: ServerStore

    @State private var showingExportSheet = false
    @State private var pendingImportFile: ImportFile?
    @State private var resultMessage: ResultMessage?

    var body: some View {
        Section {
            Button {
                showingExportSheet = true
            } label: {
                Label("Exportar conexiones…", systemImage: "square.and.arrow.up")
            }
            .disabled(store.servers.isEmpty)

            Button {
                pickImportFile()
            } label: {
                Label("Importar conexiones…", systemImage: "square.and.arrow.down")
            }

            Text("Genera un archivo .termacos cifrado con tus servidores y, si lo elegís, sus claves privadas y contraseñas guardadas. Usalo para pasar tu configuración a otra Mac con Termacos SSH.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Exportar / Importar")
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportOptionsSheet(servers: store.servers) { outcome in
                showingExportSheet = false
                switch outcome {
                case .success:
                    resultMessage = ResultMessage(
                        title: "Exportado",
                        message: "El archivo se guardó correctamente. Guardá también la contraseña que elegiste: sin ella el backup no se puede abrir.",
                        isError: false
                    )
                case .cancelled:
                    break
                case .failure(let error):
                    resultMessage = ResultMessage(title: "No se pudo exportar", message: error.localizedDescription, isError: true)
                }
            }
        }
        .sheet(item: $pendingImportFile) { file in
            ImportPassphraseSheet(data: file.data) { outcome in
                pendingImportFile = nil
                handleImportOutcome(outcome)
            }
        }
        .alert(item: $resultMessage) { result in
            Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
        }
    }

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.title = "Seleccioná el archivo de backup"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let utType = UTType(filenameExtension: ExportImportService.fileExtension) {
            panel.allowedContentTypes = [utType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            pendingImportFile = ImportFile(data: data)
        } catch {
            resultMessage = ResultMessage(title: "No se pudo leer el archivo", message: error.localizedDescription, isError: true)
        }
    }

    private func handleImportOutcome(_ outcome: Result<ImportPlan, Error>) {
        switch outcome {
        case .success(let plan):
            for server in plan.servers {
                store.upsert(server)
                if let password = plan.passwordsByAccount[server.id.uuidString] {
                    KeychainService.save(password: password, account: server.id.uuidString)
                }
            }

            var lines = ["Se importaron \(plan.serversCount) servidor(es)."]
            if plan.keysWritten > 0 {
                lines.append("\(plan.keysWritten) clave(s) privada(s) copiadas a ~/.ssh.")
            }
            if plan.passwordsAvailable > 0 {
                lines.append("\(plan.passwordsAvailable) contraseña(s) restauradas en el Llavero.")
            }
            if !plan.renamedKeyFiles.isEmpty {
                lines.append("Ya existían claves con esos nombres pero contenido distinto, así que se guardaron aparte: \(plan.renamedKeyFiles.joined(separator: ", ")).")
            }
            resultMessage = ResultMessage(title: "Importación completa", message: lines.joined(separator: "\n"), isError: false)

        case .failure(let error):
            if error is CancellationError { return }
            resultMessage = ResultMessage(title: "No se pudo importar", message: error.localizedDescription, isError: true)
        }
    }
}

private struct ImportFile: Identifiable {
    let id = UUID()
    let data: Data
}

private struct ResultMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isError: Bool
}

enum ExportOutcome {
    case success
    case cancelled
    case failure(Error)
}

// MARK: - Export sheet

private struct ExportOptionsSheet: View {
    let servers: [Server]
    let onFinish: (ExportOutcome) -> Void

    @State private var includeKeys = true
    @State private var includePasswords = false
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var errorText: String?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Qué incluir") {
                    Toggle("Claves privadas SSH", isOn: $includeKeys)
                    Toggle("Contraseñas guardadas en el Llavero", isOn: $includePasswords)
                    Text("Se exportan \(servers.count) servidor(es) con nombre, host, usuario, puerto y notas. Estos dos extras son opcionales.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Proteger el archivo") {
                    SecureField("Contraseña del archivo", text: $passphrase)
                    SecureField("Repetir contraseña", text: $confirmPassphrase)
                    Text("El archivo queda cifrado con esta contraseña. La vas a necesitar para importarlo en la otra Mac — no se puede recuperar si la perdés.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancelar") { onFinish(.cancelled) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    export()
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Exportar…")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
            }
            .padding()
        }
        .frame(width: 460, height: 430)
    }

    private func export() {
        errorText = nil
        guard !passphrase.isEmpty else {
            errorText = ExportImportError.emptyPassphrase.localizedDescription
            return
        }
        guard passphrase == confirmPassphrase else {
            errorText = ExportImportError.passphraseMismatch.localizedDescription
            return
        }

        isExporting = true
        let capturedServers = servers
        let capturedIncludeKeys = includeKeys
        let capturedIncludePasswords = includePasswords
        let capturedPassphrase = passphrase

        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ExportImportService.export(
                        servers: capturedServers,
                        includeKeys: capturedIncludeKeys,
                        includePasswords: capturedIncludePasswords,
                        passphrase: capturedPassphrase
                    )
                }.value
                isExporting = false
                savePanel(data: data)
            } catch {
                isExporting = false
                errorText = error.localizedDescription
            }
        }
    }

    private func savePanel(data: Data) {
        let panel = NSSavePanel()
        panel.title = "Guardar backup de Termacos SSH"
        panel.nameFieldStringValue = "termacos-backup.\(ExportImportService.fileExtension)"
        if let utType = UTType(filenameExtension: ExportImportService.fileExtension) {
            panel.allowedContentTypes = [utType]
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            onFinish(.cancelled)
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            onFinish(.success)
        } catch {
            onFinish(.failure(error))
        }
    }
}

// MARK: - Import passphrase sheet

private struct ImportPassphraseSheet: View {
    let data: Data
    let onFinish: (Result<ImportPlan, Error>) -> Void

    @State private var passphrase = ""
    @State private var errorText: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Contraseña del archivo") {
                    SecureField("Contraseña", text: $passphrase)
                    Text("Es la contraseña que se eligió al exportar este archivo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancelar") { onFinish(.failure(CancellationError())) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    importNow()
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Importar")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(passphrase.isEmpty || isImporting)
            }
            .padding()
        }
        .frame(width: 380, height: 220)
    }

    private func importNow() {
        errorText = nil
        isImporting = true
        let capturedData = data
        let capturedPassphrase = passphrase

        Task {
            do {
                let plan = try await Task.detached(priority: .userInitiated) {
                    try ExportImportService.prepareImport(data: capturedData, passphrase: capturedPassphrase)
                }.value
                isImporting = false
                onFinish(.success(plan))
            } catch {
                isImporting = false
                errorText = error.localizedDescription
            }
        }
    }
}
