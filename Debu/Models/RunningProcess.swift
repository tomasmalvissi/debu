import Foundation

/// Un proceso en escucha, listo para mostrar en la tabla.
/// `struct` en Swift es un tipo por valor, como `struct` / `record struct` en C#.
nonisolated struct RunningProcess: Identifiable, Hashable, Sendable {
    let pid: Int32
    let ports: [Int]
    let parentPid: Int32
    let startDate: Date?
    let commandLine: String
    let workingDirectory: String?

    /// `Identifiable` exige un `id`: la tabla lo usa para saber qué fila es cuál (como una key en Blazor).
    var id: Int32 { pid }

    var portsText: String {
        ports.map(String.init).joined(separator: ", ")
    }

    /// Detección provisional de .NET. En la fase 3 se completa con los `.csproj` conocidos.
    /// - `dotnet ...` (dotnet run, dotnet watch, dotnet App.dll)
    /// - ejecutable compilado dentro de `bin/Debug` o `bin/Release` (lo que inicia `dotnet run`)
    /// El proceso auxiliar de `dotnet watch` no es una instancia del proyecto: queda como "Otro".
    var isDotnet: Bool {
        guard !isDotnetWatchHost else { return false }
        return executableName == "dotnet"
            || commandLine.contains("/bin/Debug/")
            || commandLine.contains("/bin/Release/")
    }

    /// Nombre del ejecutable sin la ruta, por ejemplo "dotnet" o "MiApi".
    var executableName: String {
        URL(fileURLWithPath: executablePath).lastPathComponent
    }

    /// Ruta del ejecutable: el prefijo más corto de la línea de comandos que es un archivo existente.
    /// Hace falta porque la ruta puede tener espacios ("Code Helper (Plugin).app/...").
    var executablePath: String {
        let tokens = commandLine.split(separator: " ", omittingEmptySubsequences: false)
        var candidate = ""
        for token in tokens {
            candidate = candidate.isEmpty ? String(token) : candidate + " " + token
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }
        // Sin ruta absoluta (por ejemplo "dotnet run ..."): el primer token.
        return tokens.first.map(String.init) ?? commandLine
    }

    /// Rutas que sirven para asociar el proceso con un proyecto (RF-03):
    /// directorio de trabajo, ejecutable y rutas de la línea de comandos (`--project X.csproj`, `App.dll`).
    /// Las rutas relativas se resuelven contra el directorio de trabajo y se eliminan los enlaces simbólicos.
    var candidatePaths: [String] {
        var paths: [String] = []
        if let cwd = workingDirectory { paths.append(cwd) }
        if executablePath.hasPrefix("/") { paths.append(executablePath) }

        for token in commandLine.split(separator: " ").map(String.init) where !token.contains("://") && !token.contains("=") {
            if token.hasPrefix("/") {
                paths.append(token)
            } else if token.hasSuffix(".csproj") || token.hasSuffix(".dll"), let cwd = workingDirectory {
                paths.append(cwd + "/" + token)
            }
        }
        return paths.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
    }

    /// Valores de `--urls` en la línea de comandos, si los hay.
    var urlsArgument: [URL] {
        let tokens = commandLine.split(separator: " ").map(String.init)
        guard let index = tokens.firstIndex(of: "--urls"), index + 1 < tokens.count else { return [] }
        return tokens[index + 1].split(separator: ";").compactMap { URL(string: String($0)) }
    }

    /// Proceso auxiliar de `dotnet watch`: escucha en puertos propios para recargar el navegador.
    var isDotnetWatchHost: Bool {
        commandLine.contains("dotnet-watch.dll")
    }

    /// Nombre a mostrar. Para .NET intenta deducir el proyecto; la asociación real llega en la fase 3.
    var displayName: String {
        if isDotnetWatchHost { return "dotnet watch (recarga del navegador)" }
        guard isDotnet else { return executableName }
        let tokens = commandLine.split(separator: " ").map(String.init)

        // dotnet run --project ruta/MiApi.csproj
        if let index = tokens.firstIndex(of: "--project"), index + 1 < tokens.count {
            return fileNameWithoutExtension(tokens[index + 1])
        }
        // dotnet bin/Debug/net9.0/MiApi.dll
        if let dll = tokens.first(where: { $0.hasSuffix(".dll") }) {
            return fileNameWithoutExtension(dll)
        }
        // Ejecutable compilado: bin/Debug/net9.0/MiApi
        if executableName != "dotnet" {
            return executableName
        }
        // dotnet run / dotnet watch sin --project: el proyecto es el directorio de trabajo.
        if let cwd = workingDirectory {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return executableName
    }

    private func fileNameWithoutExtension(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
