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
                Label("Detener", systemImage: "stop.fill")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
        }
    }
}
