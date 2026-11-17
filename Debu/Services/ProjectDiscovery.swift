import Foundation

/// Busca proyectos web .NET dentro de las carpetas raíz (RF-11) y lee sus perfiles (RF-12).
nonisolated enum ProjectDiscovery {

    /// Carpetas que no se recorren: compilados, dependencias y repositorios.
    /// Las carpetas ocultas (`.git`, `.vs`, `.idea`) se omiten siempre.
    static let skippedFolders: Set<String> = ["bin", "obj", "node_modules", "packages", "TestResults"]

    /// `@concurrent` hace que la función corra en un hilo de fondo aunque la llame la interfaz
    /// (como un `Task.Run` en .NET). Recorrer carpetas grandes puede tardar.
    @concurrent
    static func discover(in roots: [String]) async -> [DotnetProject] {
        var projects: [String: DotnetProject] = [:]
        for root in roots {
            for csproj in csprojFiles(under: root) {
                if let project = loadProject(csproj) {
                    projects[project.id] = project  // si dos raíces se solapan, el proyecto aparece una vez
                }
            }
        }
        return projects.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Recorre `root` de forma recursiva y devuelve las rutas de los `.csproj`.
    private static func csprojFiles(under root: String) -> [String] {
        let rootURL = URL(fileURLWithPath: root).resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [String] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skippedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
            } else if url.pathExtension == "csproj" {
                result.append(url.path)
            }
        }
        return result
    }

    /// Lee un `.csproj`. Devuelve `nil` si no es un proyecto web.
    private static func loadProject(_ csprojPath: String) -> DotnetProject? {
        guard let content = try? String(contentsOfFile: csprojPath, encoding: .utf8) else { return nil }
        let directory = URL(fileURLWithPath: csprojPath).deletingLastPathComponent().resolvingSymlinksInPath().path
        let launchSettingsPath = directory + "/Properties/launchSettings.json"
        let hasLaunchSettings = FileManager.default.fileExists(atPath: launchSettingsPath)

        let isWeb = content.contains("Microsoft.NET.Sdk.Web")
            || content.contains("Microsoft.NET.Sdk.BlazorWebAssembly")
            || hasLaunchSettings
        guard isWeb else { return nil }

        return DotnetProject(
            csprojPath: csprojPath,
            name: URL(fileURLWithPath: csprojPath).deletingPathExtension().lastPathComponent,
            directory: directory,
            profiles: hasLaunchSettings ? readProfiles(launchSettingsPath) : [],
            hasUserSecrets: content.contains("<UserSecretsId>")
        )
    }

    /// Estructura mínima de `launchSettings.json`. `Decodable` es como deserializar con System.Text.Json.
    private struct LaunchSettingsFile: Decodable {
        let profiles: [String: Profile]?

        struct Profile: Decodable {
            let commandName: String?
            let applicationUrl: String?
        }
    }

    private static func readProfiles(_ path: String) -> [LaunchProfile] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true  // tolera comentarios y comas finales, como hace .NET
        guard let file = try? decoder.decode(LaunchSettingsFile.self, from: data),
              let profiles = file.profiles else { return [] }

        // Un diccionario no conserva el orden: se ordena según dónde aparece cada nombre en el texto.
        let text = String(decoding: data, as: UTF8.self)
        func position(_ name: String) -> Int {
            guard let range = text.range(of: "\"\(name)\"") else { return .max }
            return text.distance(from: text.startIndex, to: range.lowerBound)
        }

        return profiles
            .filter { ($0.value.commandName ?? "Project") == "Project" }  // IIS Express no aplica en macOS
            .sorted { position($0.key) < position($1.key) }
            .map { name, profile in
                LaunchProfile(
                    name: name,
                    applicationUrls: (profile.applicationUrl ?? "")
                        .split(separator: ";")
                        .compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
                )
            }
    }
}
