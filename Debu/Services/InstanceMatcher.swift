import Foundation

/// Asocia cada proceso en escucha con un proyecto y arma los grupos por proyecto (RF-02, RF-03, RF-04).
nonisolated enum InstanceMatcher {

    struct Result: Sendable {
        /// Instancias por id de proyecto, de la más reciente a la más antigua.
        var instancesByProject: [String: [RunningProcess]] = [:]
        /// Procesos en escucha sin proyecto: van a "Otros puertos".
        var unmatched: [RunningProcess] = []
        /// Proyecto asociado a cada PID.
        var projectByPid: [Int32: DotnetProject] = [:]
    }

    static func match(_ processes: [RunningProcess], projects: [DotnetProject]) -> Result {
        var result = Result()
        for process in processes {
            if let project = project(for: process, in: projects) {
                result.instancesByProject[project.id, default: []].append(process)
                result.projectByPid[process.pid] = project
            } else {
                result.unmatched.append(process)
            }
        }
        for key in result.instancesByProject.keys {
            result.instancesByProject[key]?.sort { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        }
        return result
    }

    /// Gana la carpeta de proyecto más específica (la más larga) que contenga alguna ruta del proceso.
    static func project(for process: RunningProcess, in projects: [DotnetProject]) -> DotnetProject? {
        guard !process.isDotnetWatchHost else { return nil }
        let paths = process.candidatePaths

        let best = projects
            .filter { project in paths.contains { isInside($0, project.directory) } }
            .max { $0.directory.count < $1.directory.count }
        guard let best else { return nil }

        // Solo cuenta como instancia si es un proceso .NET o su ejecutable está dentro del proyecto
        // (una app compilada). Que solo coincida el directorio de trabajo no alcanza:
        // otras herramientas (Claude Code, Node) también escuchan con el directorio en el proyecto.
        let executableInside = isInside(
            URL(fileURLWithPath: process.executablePath).resolvingSymlinksInPath().path, best.directory)
        return process.isDotnet || executableInside ? best : nil
    }

    /// Protocolo de un puerto (implementación: comparar con `applicationUrl` de los perfiles).
    /// También se consideran las URLs pasadas con `--urls`.
    static func scheme(forPort port: Int, process: RunningProcess, project: DotnetProject?) -> String? {
        let urls = process.urlsArgument + (project?.profiles.flatMap(\.applicationUrls) ?? [])
        return urls.first { $0.port == port }?.scheme?.uppercased()
    }

    private static func isInside(_ path: String, _ directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
    }
}
