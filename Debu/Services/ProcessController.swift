import Foundation

/// Detiene instancias respetando el árbol de procesos (RF-07).
/// En la fase 4 se suma el inicio de proyectos y en la fase 5 el reinicio.
nonisolated enum ProcessController {

    enum StopError: LocalizedError {
        case protectedProcess(Int32)
        case notRunning(Int32)
        case permissionDenied(Int32)
        case stillRunning([Int32])

        var errorDescription: String? {
            switch self {
            case .protectedProcess(let pid):
                "El proceso \(pid) no se puede detener desde Debu."
            case .notRunning(let pid):
                "El proceso \(pid) ya no está en ejecución."
            case .permissionDenied(let pid):
                "No hay permiso para detener el proceso \(pid) (pertenece a otro usuario o se inició con sudo)."
            case .stillRunning(let pids):
                "Estos procesos siguen vivos después de forzar la detención: \(pids.map(String.init).joined(separator: ", "))."
            }
        }
    }

    /// Detiene `pid` junto con su lanzador (`dotnet run` / `dotnet watch`) y todos sus hijos.
    /// - Parameter expectedStart: hora de inicio que mostraba la tabla. Si no coincide, el PID fue
    ///   reutilizado por otro proceso y no se toca nada.
    /// - Returns: los PIDs detenidos.
    @discardableResult
    static func stop(pid: Int32, expectedStart: Date?) async throws -> [Int32] {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        guard pid > 1, pid != ownPid else { throw StopError.protectedProcess(pid) }

        // 1. Comprobar que el PID sigue siendo el mismo proceso.
        let current = try await ProcessInspector.inspect([pid])
        guard let details = current[pid] else { throw StopError.notRunning(pid) }
        if let expectedStart, let actualStart = details.startDate, expectedStart != actualStart {
            throw StopError.notRunning(pid)
        }

        // 2. Foto de todos los procesos: se toma antes de matar nada, porque al morir el padre
        //    los hijos pasan a depender de launchd (PID 1) y se pierde la relación.
        let snapshot = try await ProcessSnapshot.capture()

        // 3. Subir mientras el padre sea `dotnet run` o `dotnet watch`.
        var root = pid
        while let parent = snapshot.parentPid[root], parent > 1, parent != ownPid,
              let command = snapshot.commandLine[parent], isDotnetLauncher(command) {
            root = parent
        }

        // 4. Raíz + todos sus descendientes, separados en lanzadores y aplicación.
        let tree = [root] + snapshot.descendants(of: root).filter { $0 != ownPid }
        let launchers = tree.filter { snapshot.commandLine[$0].map(isDotnetLauncher) ?? false }
        let apps = tree.filter { !launchers.contains($0) }

        // Permiso: si no se puede señalar la raíz, se informa sin tocar el resto.
        try sendSignal(0, to: root, isTarget: true)

        // 5. Primero los lanzadores: si muere solo la app, `dotnet watch` la vuelve a iniciar.
        //    `dotnet watch` ignora SIGTERM y SIGINT, así que pasados 2 segundos se fuerza con SIGKILL.
        //    No pierde nada: es una herramienta de desarrollo, no la aplicación.
        try await terminate(launchers, graceful: .seconds(2))

        // 6. Después la aplicación: SIGTERM para que ASP.NET Core cierre de forma ordenada,
        //    hasta 5 segundos de espera y SIGKILL si sigue viva.
        try await terminate(apps, graceful: .seconds(5))

        return tree
    }

    /// SIGTERM, espera hasta `graceful` y SIGKILL a los que sigan vivos.
    private static func terminate(_ pids: [Int32], graceful: Duration) async throws {
        guard !pids.isEmpty else { return }
        for pid in pids {
            try? sendSignal(SIGTERM, to: pid, isTarget: false)
        }
        var alive = await waitForExit(pids, timeout: graceful)
        guard !alive.isEmpty else { return }
        for pid in alive {
            try? sendSignal(SIGKILL, to: pid, isTarget: false)
        }
        alive = await waitForExit(alive, timeout: .seconds(1))
        guard alive.isEmpty else { throw StopError.stillRunning(alive) }
    }

    /// `dotnet run ...`, `dotnet watch ...` o el host interno `dotnet .../dotnet-watch.dll ...`.
    static func isDotnetLauncher(_ commandLine: String) -> Bool {
        let tokens = commandLine.split(separator: " ")
        guard tokens.count > 1,
              URL(fileURLWithPath: String(tokens[0])).lastPathComponent == "dotnet" else { return false }
        return tokens[1] == "run" || tokens[1] == "watch" || tokens[1].hasSuffix("dotnet-watch.dll")
    }

    // MARK: - Señales

    /// `kill` de Darwin: envía una señal a un proceso (similar a `Process.Kill()`, pero eligiendo la señal).
    /// SIGTERM pide terminar de forma ordenada; SIGKILL termina sin aviso.
    private static func sendSignal(_ signal: Int32, to pid: Int32, isTarget: Bool) throws {
        guard kill(pid, signal) != 0 else { return }
        switch errno {
        case ESRCH:
            // Ya terminó: no es un error.
            return
        case EPERM:
            throw StopError.permissionDenied(pid)
        default:
            if isTarget { throw StopError.notRunning(pid) }
        }
    }

    /// `kill(pid, 0)` no envía nada: solo comprueba si el proceso existe.
    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Espera hasta que terminen los procesos o se agote el tiempo. Devuelve los que siguen vivos.
    private static func waitForExit(_ pids: [Int32], timeout: Duration) async -> [Int32] {
        let deadline = ContinuousClock.now + timeout
        var alive = pids.filter(isAlive)
        while !alive.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            alive = alive.filter(isAlive)
        }
        return alive
    }
}

/// Relación padre-hijo y línea de comandos de todos los procesos del sistema en un momento dado.
nonisolated struct ProcessSnapshot: Sendable {
    let parentPid: [Int32: Int32]
    let commandLine: [Int32: String]

    static func capture() async throws -> ProcessSnapshot {
        let result = try await ShellRunner.run("/bin/ps", ["-A", "-o", "pid=,ppid=,command="])
        var parents: [Int32: Int32] = [:]
        var commands: [Int32: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            parents[pid] = ppid
            commands[pid] = String(parts[2])
        }
        return ProcessSnapshot(parentPid: parents, commandLine: commands)
    }

    /// Hijos, nietos, etc. (recorrido en anchura).
    func descendants(of root: Int32) -> [Int32] {
        var childrenByParent: [Int32: [Int32]] = [:]
        for (pid, parent) in parentPid {
            childrenByParent[parent, default: []].append(pid)
        }
        var result: [Int32] = []
        var queue = childrenByParent[root] ?? []
        while !queue.isEmpty {
            let pid = queue.removeFirst()
            result.append(pid)
            queue.append(contentsOf: childrenByParent[pid] ?? [])
        }
        return result
    }
}
