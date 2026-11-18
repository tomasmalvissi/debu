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
    /// Ícono propio del proyecto (favicon en wwwroot), si tiene. Si no, se muestra un monograma.
    var iconPath: String? = nil

    var id: String { csprojPath }

    /// Iniciales para el monograma: "Ubicuo.API" → "UA", "TestApi" → "TA", "Plataforma.Web" → "PW".
    var monogram: String {
        let parts = name.split(whereSeparator: { ".-_ ".contains($0) })
        if parts.count >= 2 {
            return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        let capitals = name.filter(\.isUppercase)
        if capitals.count >= 2 { return String(capitals.prefix(2)) }
        return String(name.prefix(2)).uppercased()
    }
}
