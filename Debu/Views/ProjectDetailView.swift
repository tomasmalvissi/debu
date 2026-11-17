import SwiftUI

/// Panel derecho de un proyecto: inicio, acciones sobre sus instancias, tabla de instancias y logs.
struct ProjectDetailView: View {
    @Environment(AppState.self) private var appState
    let project: DotnetProject

    @State private var confirmStopAll = false
    /// Instancia elegida en la tabla: sus logs se muestran abajo.
    @State private var selectedPid: Int32?

    var body: some View {
        let instances = appState.instances(of: project)
        let starting = appState.startingLaunches(of: project)

        VStack(alignment: .leading, spacing: 12) {
            header(instances)
            startPanel(isStarting: !starting.isEmpty)

            if instances.isEmpty {
                if starting.isEmpty {
                    ContentUnavailableView(
                        "Sin instancias en ejecución",
                        systemImage: "pause.circle",
                        description: Text("Iniciá el proyecto con el botón Iniciar.")
                    )
                    .frame(maxHeight: 160)
                }
            } else {
                instancesTable(instances)
                    .frame(minHeight: 90, idealHeight: 140, maxHeight: 200)
            }

            if let launch = displayedLaunch(instances) {
                LogView(launch: launch)
            } else if !instances.isEmpty {
                Text("Los logs solo están disponibles para las instancias iniciadas desde Debu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(project.name)
        .confirmationDialog(
            "¿Detener las \(instances.count) instancias de \(project.name)?",
            isPresented: $confirmStopAll
        ) {
            Button("Detener todas", role: .destructive) {
                Task { await appState.stopAll(of: project) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        // RF-14: aviso de instancia existente con opción de reemplazo.
        .alert(
            "\(project.name) ya está en ejecución",
            isPresented: Binding(
                get: { appState.pendingReplaceProjectId == project.id },
                set: { if !$0 { appState.pendingReplaceProjectId = nil } }
            )
        ) {
            Button("Reemplazar") {
                Task { await appState.replaceAndStart(project) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se permite una sola instancia por proyecto. «Reemplazar» detiene la actual e inicia una nueva.")
        }
    }

    /// Logs a mostrar: los de la instancia elegida si la inició Debu; si no, la última ejecución del proyecto.
    private func displayedLaunch(_ instances: [RunningProcess]) -> AppLaunch? {
        if let pid = selectedPid, let process = instances.first(where: { $0.pid == pid }) {
            return appState.launch(for: process)
        }
        return appState.launches(of: project).first
    }

    // MARK: - Encabezado

    private func header(_ instances: [RunningProcess]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.title2.bold())
            Text(project.directory)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if instances.count > 1 {
                Label("Hay \(instances.count) instancias de este proyecto en ejecución.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            HStack {
                // RF-09
                Button {
                    confirmStopAll = true
                } label: {
                    Label("Detener todas", systemImage: "stop.fill")
                }
                .disabled(instances.isEmpty)

                Button {
                    Task { await appState.stopAllButNewest(of: project) }
                } label: {
                    Label("Detener todas salvo la más reciente", systemImage: "stop.circle")
                }
                .disabled(instances.count < 2)
            }
        }
    }

    // MARK: - Iniciar (RF-12, RF-13)

    private func startPanel(isStarting: Bool) -> some View {
        // Bindings "calculados": leen y escriben en AppState (como una propiedad con get/set en C#).
        let profileBinding = Binding<String>(
            get: { appState.selectedProfile(for: project) ?? "" },
            set: { appState.setSelectedProfile($0, for: project) }
        )
        let secretsBinding = Binding<Bool>(
            get: { appState.withSecrets(for: project) },
            set: { appState.setWithSecrets($0, for: project) }
        )

        return GroupBox {
            HStack(spacing: 16) {
                if project.profiles.isEmpty {
                    Text("Sin launchSettings.json: se usa la configuración por defecto.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Perfil", selection: profileBinding) {
                        ForEach(project.profiles, id: \.name) { profile in
                            Text("\(profile.name)  ·  \(profile.applicationUrls.map(\.absoluteString).joined(separator: ", "))")
                                .tag(profile.name)
                        }
                    }
                    .fixedSize()
                }

                Toggle("Con secretos", isOn: secretsBinding)
                    .toggleStyle(.switch)
                    .disabled(!project.hasUserSecrets)
                    .help(project.hasUserSecrets
                          ? "Sin secretos: se inicia sin cargar los user-secrets del proyecto."
                          : "Este proyecto no usa user-secrets.")

                Spacer()

                if isStarting {
                    ProgressView().controlSize(.small)
                    Text("Iniciando…").foregroundStyle(.secondary)
                }
                Button {
                    appState.start(project)
                } label: {
                    Label("Iniciar", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(4)
        }
    }

    // MARK: - Instancias

    private func instancesTable(_ instances: [RunningProcess]) -> some View {
        Table(instances, selection: $selectedPid) {
            TableColumn("Puertos") { process in
                HStack(spacing: 6) {
                    Text(appState.portsDescription(of: process)).monospacedDigit()
                    if instances.count > 1 && process.id == instances.first?.id {
                        Text("más reciente")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
                .help(process.commandLine)
            }
            TableColumn("PID") { process in
                Text(String(process.pid)).monospacedDigit()
            }
            .width(min: 50, ideal: 70)
            TableColumn("Origen") { process in
                Text(appState.launch(for: process) != nil ? "Debu" : "Externa")
                    .foregroundStyle(appState.launch(for: process) != nil ? .primary : .secondary)
            }
            .width(min: 60, ideal: 70)
            TableColumn("En ejecución") { process in
                if let start = process.startDate {
                    Text(start, style: .relative)
                } else {
                    Text("—")
                }
            }
            .width(min: 90, ideal: 130)
            TableColumn("Acciones") { process in
                InstanceActions(process: process)
            }
            .width(min: 400, ideal: 420)
        }
    }
}

/// Botones de una instancia: Abrir en navegador, Copiar URL, Reiniciar y Detener (RF-07, RF-08, RF-10).
private struct InstanceActions: View {
    @Environment(AppState.self) private var appState
    let process: RunningProcess

    var body: some View {
        HStack(spacing: 6) {
            if let url = appState.url(of: process) {
                Button {
                    NSWorkspace.shared.open(url)  // abre con el navegador predeterminado
                } label: {
                    Label("Abrir", systemImage: "safari")
                }
                .help(url.absoluteString)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Label("Copiar URL", systemImage: "link")
                }
                .help(url.absoluteString)
            }

            if appState.restartingPids.contains(process.pid) {
                ProgressView().controlSize(.small)
                Text("Reiniciando…").foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await appState.restart(process) }
                } label: {
                    Label("Reiniciar", systemImage: "arrow.counterclockwise")
                }
                .help(appState.launch(for: process) == nil
                      ? "Al reiniciar una instancia externa, la nueva queda a cargo de Debu: se pierde la terminal o la sesión de depuración original."
                      : "Detiene la instancia y la vuelve a iniciar con el mismo perfil.")
                StopButton(process: process)
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }
}
