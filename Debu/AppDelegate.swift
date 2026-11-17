import AppKit

/// Delegado de la aplicación: recibe eventos del ciclo de vida, como el arranque o el intento de salir.
/// Es el equivalente a `IHostApplicationLifetime` (ApplicationStarted / ApplicationStopping), pero puede cancelar la salida.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Búsqueda de proyectos y refresco periódico, aunque la ventana principal esté cerrada.
        appState.startBackgroundWork()
    }

    /// Al cerrar la ventana la app sigue en la barra de menú.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !appState.runningLaunches.isEmpty else { return .terminateNow }

        // Decisión del proyecto: al salir, preguntar qué hacer con las instancias iniciadas por Debu.
        let count = appState.runningLaunches.count
        let alert = NSAlert()
        alert.messageText = count == 1
            ? "Hay 1 instancia iniciada por Debu en ejecución"
            : "Hay \(count) instancias iniciadas por Debu en ejecución"
        alert.informativeText = "Si las dejás corriendo, siguen funcionando pero Debu deja de mostrar sus logs."
        alert.addButton(withTitle: "Detenerlas y salir")
        alert.addButton(withTitle: "Dejarlas corriendo")
        alert.addButton(withTitle: "Cancelar")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // La salida queda en espera hasta que terminen de detenerse.
            Task {
                await appState.stopAllLaunches()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
