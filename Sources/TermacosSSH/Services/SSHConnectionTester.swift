import Foundation

struct SSHConnectionTestOutcome {
    let succeeded: Bool
    let message: String
}

enum SSHConnectionTester {
    static func test(server: Server, password: String?) async -> SSHConnectionTestOutcome {
        await Task.detached(priority: .userInitiated) {
            runTest(server: server, password: password)
        }.value
    }

    private static func runTest(server: Server, password: String?) -> SSHConnectionTestOutcome {
        var environment = ProcessInfo.processInfo.environment
        let askpassURL = makeAskpassScriptIfNeeded(password: password)
        defer {
            if let askpassURL {
                try? FileManager.default.removeItem(at: askpassURL)
            }
        }

        if let askpassURL, let password {
            environment["SSH_ASKPASS"] = askpassURL.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["TERMACOS_TEST_PASSWORD"] = password
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
                message: "La prueba agotó el tiempo de espera. Revisa host, puerto o conectividad."
            )
        }

        guard process.terminationStatus == 0 else {
            return SSHConnectionTestOutcome(
                succeeded: false,
                message: explainFailure(output: rawOutput, exitCode: process.terminationStatus)
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

    private static func makeAskpassScriptIfNeeded(password: String?) -> URL? {
        guard let password, !password.isEmpty else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("termacos-test-askpass-\(UUID().uuidString).sh")
        let content = """
        #!/bin/sh
        printf '%s\\n' "$TERMACOS_TEST_PASSWORD"
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

    private static func explainFailure(output: String, exitCode: Int32) -> String {
        let lowercased = output.lowercased()

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
            return "La conexión agotó el tiempo de espera. Revisa red, host o firewall."
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

        if let reason = SSHExitCode.description(for: exitCode) {
            return reason
        }
        return "No se pudo completar la prueba de conexión."
    }
}
