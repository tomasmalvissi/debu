import Foundation

/// Un perfil de `Properties/launchSettings.json` con `commandName: "Project"`.
nonisolated struct LaunchProfile: Hashable, Sendable {
    let name: String
    let applicationUrls: [URL]
}

/// Un proyecto web .NET encontrado en las carpetas raíz.
nonisolated struct DotnetProject: Identifiable, Hashable, Sendable {
    /// Ruta completa del `.csproj`: identifica al proyecto aunque dos se llamen igual.
    let csprojPath: String
    /// Nombre del `.csproj` sin extensión.
    let name: String
    /// Carpeta del `.csproj`, sin enlaces simbólicos (como la devuelve `lsof`).
    let directory: String
    /// Perfiles en el mismo orden que el archivo: `dotnet run` usa el primero por defecto.
    let profiles: [LaunchProfile]
    /// Tiene `<UserSecretsId>` en el `.csproj` (se usa en la fase 4).
    let hasUserSecrets: Bool

    var id: String { csprojPath }
}
