import Foundation

/// Un proceso que escucha en uno o más puertos TCP.
nonisolated struct ListeningSocket: Sendable {
    let pid: Int32
    let ports: [Int]
}

/// Obtiene los procesos en escucha con `lsof`.
nonisolated enum PortScanner {

    static func scan() async throws -> [ListeningSocket] {
        // -n/-P: no resolver nombres ni puertos · -iTCP -sTCP:LISTEN: solo sockets TCP en escucha
        // -F pn: salida en campos, una línea por campo (p = PID, n = dirección:puerto)
        let result = try await ShellRunner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pn"])
        // lsof devuelve 1 cuando no encuentra nada: no es un error.
        return parse(result.stdout)
    }

    /// Convierte la salida de `lsof -F pn` en una lista de procesos con sus puertos.
    static func parse(_ output: String) -> [ListeningSocket] {
        var portsByPid: [Int32: Set<Int>] = [:]
        var order: [Int32] = []
        var currentPid: Int32?

        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = line.dropFirst()
            switch field {
            case "p":
                currentPid = Int32(value)
                if let pid = currentPid, portsByPid[pid] == nil {
                    portsByPid[pid] = []
                    order.append(pid)
                }
            case "n":
                // Formatos: "*:5000", "127.0.0.1:5000", "[::1]:5000". El puerto va después del último ":".
                if let pid = currentPid,
                   let colon = value.lastIndex(of: ":"),
                   let port = Int(value[value.index(after: colon)...]) {
                    // Set: el mismo puerto en IPv4 e IPv6 se cuenta una sola vez.
                    portsByPid[pid, default: []].insert(port)
                }
            default:
                break
            }
        }

        return order.map { ListeningSocket(pid: $0, ports: portsByPid[$0, default: []].sorted()) }
    }
}
