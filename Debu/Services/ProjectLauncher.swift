import Foundation

/// Inicio de proyectos con `dotnet run` (RF-12, RF-13). Forma parte de las responsabilidades de ProcessController.
extension ProcessController {

    enum StartError: LocalizedError {
        case dotnetNotFound

        var errorDescription: String? {
            switch self {
            case .dotnetNotFound:
                "No se encontró el ejecutable dotnet. Configurá su ruta en Debu > Settings…"
            }
        }
    }

    /// Inicia `dotnet run --project <csproj> [--launch-profile <perfil>]`.
    /// - Parameter withSecrets: `false` desactiva los user-secrets apuntando `APPDATA` a una carpeta vacía.
    ///   .NET busca los secretos en `$APPDATA/Microsoft/UserSecrets` si esa variable existe, y si no en
    ///   `~/.microsoft/usersecrets`. El entorno sigue siendo `Development`, así que se carga el mismo appsettings.
    static func start(
        project: DotnetProject,
        profile: String?,
        withSecrets: Bool,
        urls: [String] = [],
        dotnetPath: String,
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> Process {
        var arguments = ["run", "--project", project.csprojPath]
        if let profile {
            arguments += ["--launch-profile", profile]
        }
        // Lo que va después de "--" se le pasa a la aplicación, no a dotnet run.
        // --urls tiene prioridad sobre el applicationUrl del perfil.
        if !urls.isEmpty {
            arguments += ["--", "--urls", urls.joined(separator: ";")]
        }

        var environment = ProcessInfo.processInfo.environment
        // Una app abierta desde el Finder no hereda el PATH de la terminal: se agregan las rutas habituales
        // para que la compilación encuentre dotnet y otras herramientas (node, npm).
        let dotnetDirectory = URL(fileURLWithPath: dotnetPath).deletingLastPathComponent().path
        let extraPaths = [dotnetDirectory, "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (extraPaths + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"])
            .joined(separator: ":")
        environment["DOTNET_NOLOGO"] = "1"
        if !withSecrets {
            environment["APPDATA"] = try emptyAppDataDirectory()
        }

        return try ShellRunner.start(
            dotnetPath,
            arguments,
            workingDirectory: project.directory,
            environment: environment,
            onOutput: onOutput,
            onExit: onExit
        )
    }

    /// Carpeta vacía en Application Support que hace de `APPDATA` sin secretos.
    private static func emptyAppDataDirectory() throws -> String {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Debu/sin-secretos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }
}

/// Busca el ejecutable `dotnet` (regla de implementación: la app no hereda el PATH de la terminal).
nonisolated enum DotnetLocator {
    static let candidates = ["/usr/local/share/dotnet/dotnet", "/opt/homebrew/bin/dotnet"]

    /// La ruta configurada si existe; si no, la primera de las ubicaciones habituales.
    static func resolve(configured: String) -> String? {
        let trimmed = configured.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return FileManager.default.isExecutableFile(atPath: trimmed) ? trimmed : nil
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
