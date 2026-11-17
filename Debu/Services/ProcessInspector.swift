import Foundation

/// Datos de un proceso obtenidos con `ps` y `lsof`.
nonisolated struct ProcessDetails: Sendable {
    let pid: Int32
    let parentPid: Int32
    let startDate: Date?
    let commandLine: String
    var workingDirectory: String?
}

/// Dado un conjunto de PIDs, obtiene PID padre, hora de inicio, línea de comandos y directorio de trabajo.
nonisolated enum ProcessInspector {

    static func inspect(_ pids: [Int32]) async throws -> [Int32: ProcessDetails] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")

        // Las dos consultas se lanzan en paralelo (como Task.WhenAll).
        // LC_ALL=C: el formato de lstart no depende del idioma del sistema.
        async let psResult = ShellRunner.run(
            "/bin/ps", ["-p", pidList, "-o", "pid=,ppid=,lstart=,command="], environment: ["LC_ALL": "C"])
        async let cwdResult = ShellRunner.run(
            "/usr/sbin/lsof", ["-a", "-p", pidList, "-d", "cwd", "-F", "n"])

        var details = parsePs(try await psResult.stdout)
        for (pid, cwd) in parseCwd(try await cwdResult.stdout) {
            details[pid]?.workingDirectory = cwd
        }
        return details
    }

    /// Cada línea: `PID PPID Día Mes Fecha Hora Año comando completo...`
    static func parsePs(_ output: String) -> [Int32: ProcessDetails] {
        var result: [Int32: ProcessDetails] = [:]
        for line in output.split(separator: "\n") {
            // 7 cortes: pid, ppid, 5 partes de la fecha y el resto es el comando (que puede tener espacios).
            let parts = line.split(maxSplits: 7, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 8, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            let dateText = parts[2...6].joined(separator: " ")
            result[pid] = ProcessDetails(
                pid: pid,
                parentPid: ppid,
                startDate: lstartFormatter.date(from: dateText),
                commandLine: String(parts[7]),
                workingDirectory: nil
            )
        }
        return result
    }

    /// Salida de `lsof -F n`: líneas `p<PID>`, `fcwd`, `n<ruta>`.
    static func parseCwd(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var currentPid: Int32?
        for line in output.split(separator: "\n") {
            switch line.first {
            case "p": currentPid = Int32(line.dropFirst())
            case "n": if let pid = currentPid { result[pid] = String(line.dropFirst()) }
            default: break
            }
        }
        return result
    }

    /// Formato de lstart con LC_ALL=C, por ejemplo "Fri Nov 13 08:30:46 2026".
    private static let lstartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()
}
