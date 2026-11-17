import Foundation
import Observation

/// Un `dotnet run` iniciado por Debu, con su salida de consola (RF-15).
/// Es una `class` (tipo por referencia) porque la salida llega de a poco y la vista tiene que ver cada cambio.
@Observable
final class AppLaunch: Identifiable {
    let id = UUID()
    let projectId: String
    let projectName: String
    let profile: String?
    let withSecrets: Bool
    /// URLs explícitas pasadas con `--urls` (en reinicios de instancias externas). Vacío = las del perfil.
    let urls: [String]
    let startedAt = Date()

    /// PID del `dotnet run`. La instancia que escucha en el puerto es su proceso hijo.
    var pid: Int32 = 0
    /// Código de salida cuando terminó; `nil` mientras corre.
    var exitCode: Int32?
    var isRunning: Bool { exitCode == nil }

    /// Líneas de salida. Se guardan las últimas `maxLines` para no crecer sin límite.
    private(set) var lines: [String] = []
    private var partialLine = ""
    private let maxLines = 5000

    /// El objeto Process se conserva mientras corre; la vista no lo observa.
    @ObservationIgnored var process: Process?

    init(project: DotnetProject, profile: String?, withSecrets: Bool, urls: [String] = []) {
        projectId = project.id
        projectName = project.name
        self.profile = profile
        self.withSecrets = withSecrets
        self.urls = urls
    }

    /// Agrega texto de la consola. Puede llegar cortado a mitad de línea.
    func append(_ text: String) {
        let combined = partialLine + text
        var newLines = combined.components(separatedBy: "\n")
        partialLine = newLines.removeLast()  // lo que quedó después del último salto de línea
        lines.append(contentsOf: newLines.map(Self.stripAnsiCodes))
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    /// Al terminar, se agrega la última línea incompleta, si la hay.
    func finish(exitCode: Int32) {
        if !partialLine.isEmpty {
            lines.append(Self.stripAnsiCodes(partialLine))
            partialLine = ""
        }
        self.exitCode = exitCode
        process = nil
    }

    /// Indica que HTTPS falló por falta del certificado de desarrollo.
    var needsDevCertificate: Bool {
        lines.contains { $0.contains("Unable to configure HTTPS endpoint") || $0.contains("dotnet dev-certs https") }
    }

    /// Quita los códigos de color de terminal (ESC[...m).
    private nonisolated static func stripAnsiCodes(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}
