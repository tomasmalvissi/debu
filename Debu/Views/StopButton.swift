import SwiftUI

/// Botón "Detener" de una fila. Mientras se detiene, muestra un indicador.
struct StopButton: View {
    @Environment(AppState.self) private var appState

    let process: RunningProcess
    /// Acción al pulsar. Por defecto detiene sin preguntar; "Otros puertos" la usa para pedir confirmación.
    var action: (() -> Void)?

    var body: some View {
        if appState.stoppingPids.contains(process.pid) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Deteniendo…").foregroundStyle(.secondary)
            }
        } else {
            Button {
                if let action {
                    action()
                } else {
                    Task { await appState.stop(process) }
                }
            } label: {
                Label {
                    Text("Detener")
                } icon: {
                    // Rojo: único color de acento de la app, reservado para detener y para los duplicados.
                    Image(systemName: "stop.fill").foregroundStyle(.red)
                }
                .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
        }
    }
}
