import Foundation

/// Resultado de ejecutar un comando (como el ExitCode + StandardOutput/StandardError de System.Diagnostics.Process).
nonisolated struct ShellResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Ejecuta comandos del sistema fuera del hilo principal.
nonisolated enum ShellRunner {

    /// Inicia un proceso de larga duración y entrega su salida a medida que llega (streaming, para logs).
    /// stdout y stderr van al mismo canal para conservar el orden de los mensajes.
    /// - Returns: el `Process`, que hay que conservar mientras corre.
    static func start(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: String,
        environment: [String: String],
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice  // sin entrada: nada queda esperando el teclado

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Se llama en un hilo de fondo cada vez que hay datos nuevos (como el evento OutputDataReceived).
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil  // fin de la salida
            } else {
                onOutput(String(decoding: data, as: UTF8.self))
            }
        }
        // Equivale al evento Exited de System.Diagnostics.Process.
        process.terminationHandler = { finished in
            onExit(finished.terminationStatus)
        }

        try process.run()
        return process
    }

    /// Ejecuta `executable` con `arguments` y espera a que termine.
    /// - Parameter environment: variables extra que se suman a las del proceso actual.
    static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            // Process es bloqueante: se ejecuta en una cola de fondo para no congelar la interfaz.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runBlocking(executable, arguments, environment))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        _ executable: String,
        _ arguments: [String],
        _ environment: [String: String]
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // stdout y stderr se leen en paralelo: si uno se llena mientras se espera al otro, el proceso se bloquea.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ShellResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

/// Contenedor para pasar datos entre hilos. Lo protege el DispatchGroup de `runBlocking`.
private nonisolated final class DataBox: @unchecked Sendable {
    var data = Data()
}
