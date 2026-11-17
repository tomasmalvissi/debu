import SwiftUI

/// "Otros puertos": procesos en escucha que no se asociaron con ningún proyecto.
struct OtherPortsView: View {
    @Environment(AppState.self) private var appState

    /// Proceso no .NET a la espera de confirmación antes de detenerlo.
    @State private var pendingStop: RunningProcess?

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            Table(appState.otherProcesses) {
                TableColumn("Nombre") { process in
                    Text(process.displayName)
                        .help(process.commandLine)
                }
                TableColumn("Puertos") { process in
                    Text(appState.portsDescription(of: process)).monospacedDigit()
                }
                .width(min: 80, ideal: 130)
                TableColumn("PID") { process in
                    Text(String(process.pid)).monospacedDigit()
                }
                .width(min: 50, ideal: 70)
                TableColumn("En ejecución") { process in
                    if let start = process.startDate {
                        Text(start, style: .relative)
                    } else {
                        Text("—")
                    }
                }
                .width(min: 90, ideal: 130)
                TableColumn("Tipo") { process in
                    Text(process.isDotnet ? ".NET" : "Otro")
                        .foregroundStyle(process.isDotnet ? .primary : .secondary)
                }
                .width(min: 40, ideal: 50)
                TableColumn("Directorio") { process in
                    Text(process.workingDirectory ?? "—")
                        .foregroundStyle(.secondary)
                        .truncationMode(.head)
                }
                TableColumn("") { process in
                    if process.isDotnet {
                        StopButton(process: process)
                    } else {
                        // Criterio de diseño: confirmar antes de detener procesos que no son .NET.
                        StopButton(process: process) { pendingStop = process }
                    }
                }
                .width(min: 100, ideal: 100)
            }
            .overlay {
                if appState.otherProcesses.isEmpty && appState.lastUpdated != nil {
                    ContentUnavailableView(
                        "No hay otros puertos",
                        systemImage: "network.slash",
                        description: Text("Todos los procesos .NET en escucha pertenecen a un proyecto conocido.")
                    )
                }
            }

            Divider()

            HStack {
                // RF-06: filtro para ver también procesos que no son .NET.
                Toggle("Mostrar procesos no .NET", isOn: $appState.showNonDotnet)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .navigationTitle("Otros puertos")
        .confirmationDialog(
            "¿Detener \(pendingStop?.displayName ?? "")?",
            isPresented: Binding(
                get: { pendingStop != nil },
                set: { if !$0 { pendingStop = nil } }
            ),
            presenting: pendingStop
        ) { process in
            Button("Detener", role: .destructive) {
                Task { await appState.stop(process) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { process in
            Text("No es un proceso .NET (PID \(String(process.pid))). Detenerlo puede cerrar otra aplicación.")
        }
    }
}
