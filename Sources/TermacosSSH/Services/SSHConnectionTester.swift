import Foundation

struct SSHConnectionTestOutcome {
    let succeeded: Bool
    let message: String
}

enum SSHConnectionTester {
    static func test(server: Server, password: String?, keyPassphrase: String?) async -> SSHConnectionTestOutcome {
        await Task.detached(priority: .userInitiated) {
            runTest(server: server, password: password, keyPassphrase: keyPassphrase)
        }.value
    }

    private static func runTest(server: Server, password: String?, keyPassphrase: String?) -> SSHConnectionTestOutcome {
        if let keyValidationMessage = validateKeyIfNeeded(server) {
            return SSHConnectionTestOutcome(succeeded: false, message: keyValidationMessage)
        }

        var environment = ProcessInfo.processInfo.environment
        let askpassURL = makeAskpassScriptIfNeeded(password: password, keyPassphrase: keyPassphrase)
        defer {
            if let askpassURL {
                try? FileManager.default.removeItem(at: askpassURL)
            }
        }

        if let askpassURL {
            environment["SSH_ASKPASS"] = askpassURL.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            if let password {
                environment["TERMACOS_TEST_PASSWORD"] = password
            }
            if let keyPassphrase {
                environment["TERMACOS_TEST_KEY_PASSPHRASE"] = keyPassphrase
            }
            environment["DISPLAY"] = environment["DISPLAY"] ?? "localhost:0"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = testArguments(for: server)
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return SSHConnectionTestOutcome(
                succeeded: false,
                message: "No se pudo iniciar SSH: \(error.localizedDescription)"
            )
        }

        let timedOut = wait(for: process, timeout: 12)
        if timedOut {
            process.terminate()
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let rawOutput = String(data: data, encoding: .utf8) ?? ""

        if timedOut {
            return SSHConnectionTestOutcome(
                succeeded: false,
                message: timeoutMessage(for: server)
            )
        }

        guard process.terminationStatus == 0 else {
            return SSHConnectionTestOutcome(
                succeeded: false,
                message: explainFailure(output: rawOutput, exitCode: process.terminationStatus, server: server)
            )
        }

        return SSHConnectionTestOutcome(succeeded: true, message: "Conexión probada correctamente.")
    }

    private static func testArguments(for server: Server) -> [String] {
        [
            "-o", "ConnectTimeout=8",
            "-o", "ConnectionAttempts=1",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=no",
            "-p", String(server.port)
        ] + SSHCommandBuilder.authenticationArguments(for: server, includeAutomaticIdentity: true) + [
            "\(server.username)@\(server.host)",
            "exit"
        ]
    }

    private static func makeAskpassScriptIfNeeded(password: String?, keyPassphrase: String?) -> URL? {
        guard (password?.isEmpty == false) || (keyPassphrase?.isEmpty == false) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("termacos-test-askpass-\(UUID().uuidString).sh")
        let content = """
        #!/bin/sh
        case "$1" in
            *passphrase*|*Passphrase*)
                printf '%s\\n' "$TERMACOS_TEST_KEY_PASSPHRASE"
                ;;
            *)
                printf '%s\\n' "$TERMACOS_TEST_PASSWORD"
                ;;
        esac
        """

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private static func wait(for process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return process.isRunning
    }

    private static func explainFailure(output: String, exitCode: Int32, server: Server) -> String {
        let lowercased = output.lowercased()

        if lowercased.contains("incorrect passphrase") || lowercased.contains("bad passphrase") {
            return "Passphrase incorrecta para la clave privada."
        }
        if lowercased.contains("read_passphrase") || lowercased.contains("can't open /dev/tty") || lowercased.contains("cannot read passphrase") {
            return "La clave privada está protegida con passphrase. Ingrésala en el formulario para probar la conexión."
        }
        if lowercased.contains("load key") && lowercased.contains("invalid format") {
            return "La clave privada no tiene un formato SSH soportado."
        }
        if lowercased.contains("load key") && (lowercased.contains("no such file") || lowercased.contains("not found")) {
            return "No se encontró el archivo de clave privada seleccionado."
        }
        if lowercased.contains("load key") && lowercased.contains("permission denied") {
            return "No se pudo leer la clave privada seleccionada. Revisa permisos del archivo."
        }
        if lowercased.contains("permission denied") {
            return "Autenticación rechazada. Revisa usuario, contraseña y llave privada."
        }
        if lowercased.contains("could not resolve hostname") || lowercased.contains("nodename nor servname provided") {
            return "No se pudo resolver el host. Revisa el dominio o la IP."
        }
        if lowercased.contains("connection refused") {
            return "El servidor rechazó la conexión. Revisa el puerto SSH o el firewall."
        }
        if lowercased.contains("operation timed out") || lowercased.contains("connection timed out") {
            return timeoutMessage(for: server)
        }
        if lowercased.contains("no route to host") {
            return "No hay ruta hacia el servidor. Revisa tu red o VPN."
        }
        if lowercased.contains("host key verification failed") {
            return "No se pudo verificar la identidad del servidor. Revisa la clave del host en known_hosts."
        }
        if lowercased.contains("bad permissions") || lowercased.contains("unprotected private key file") {
            return "La llave privada tiene permisos inseguros. Debe tener permisos restringidos."
        }
        if lowercased.contains("too many authentication failures") {
            return "Demasiados intentos de autenticación. Revisa las llaves cargadas en el agente SSH."
        }

        if let reason = SSHExitCode.description(for: exitCode, server: server) {
            return reason
        }
        return "No se pudo completar la prueba de conexión."
    }

    private static func validateKeyIfNeeded(_ server: Server) -> String? {
        guard server.authenticationMode.requiresKey || server.keyPath?.isEmpty == false else { return nil }
        guard let keyPath = server.keyPath, !keyPath.isEmpty else {
            return "Selecciona una clave privada para esta conexión."
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: keyPath) else {
            return "No se encontró el archivo de clave privada seleccionado."
        }
        guard fm.isReadableFile(atPath: keyPath) else {
            return "No se pudo leer la clave privada seleccionada. Revisa permisos del archivo."
        }
        if keyPath.hasSuffix(".pub") {
            return "Seleccionaste una clave pública (.pub). Debes usar la clave privada."
        }
        return nil
    }

    private static func timeoutMessage(for server: Server) -> String {
        if server.host == "173.231.198.46" {
            return "No fue posible conectar al puerto SSH. Si es el servidor TeBusco, verifica que estés conectado a la VPN."
        }
        return "La conexión agotó el tiempo de espera. Revisa red, host, puerto, VPN o firewall."
    }
}
