import SwiftUI

/// Panel derecho de un proyecto (diseño "variante 1"):
/// encabezado, tres botones grandes para el proyecto entero, opciones de inicio, tarjetas de instancia y logs.
struct ProjectDetailView: View {
    @Environment(AppState.self) private var appState
    let project: DotnetProject

    /// Instancia elegida (clic en su tarjeta): sus logs se muestran abajo.
    @State private var selectedPid: Int32?

    var body: some View {
        let instances = appState.instances(of: project)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(instances)
                if instances.count > 1 {
                    duplicatesBanner(count: instances.count)
                }
                controlBar
                startOptions(newest: instances.first)
                if !instances.isEmpty {
                    instanceCards(instances)
                }
                logs(instances)
            }
            .padding(20)
        }
        .navigationTitle(project.name)
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

    // MARK: - Encabezado

    private func header(_ instances: [RunningProcess]) -> some View {
        HStack(spacing: 14) {
            ProjectAvatar(project: project, size: 52,
                          isRunning: appState.isRunning(project),
                          hasDuplicates: instances.count > 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.title2.weight(.semibold))
                    Button {
                        appState.toggleFavorite(project)
                    } label: {
                        Image(systemName: appState.isFavorite(project) ? "star.fill" : "star")
                            .foregroundStyle(appState.isFavorite(project) ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(appState.isFavorite(project)
                          ? "Quitar de favoritos (deja de aparecer en la barra de menú cuando está detenido)"
                          : "Agregar a favoritos (aparece siempre en la barra de menú)")
                }
                statusLine(instances)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func statusLine(_ instances: [RunningProcess]) -> some View {
        if let newest = instances.first {
            HStack(spacing: 6) {
                Circle().fill(Color.primary).frame(width: 7, height: 7)
                Text("En ejecución · \(appState.portsDescription(of: newest))")
                if let start = newest.startDate {
                    Text("· hace \(Text(start, style: .relative))")
                }
            }
        } else if !appState.startingLaunches(of: project).isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Iniciando…")
            }
        } else {
            Text("Detenido")
        }
    }

    private func duplicatesBanner(count: Int) -> some View {
        HStack {
            Label("\(count) instancias en ejecución: se permite una.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Spacer()
            // RF-09: detener todas salvo la más reciente.
            Button("Dejar solo la más reciente") {
                Task { await appState.stopAllButNewest(of: project) }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Botones del proyecto

    private var controlBar: some View {
        let running = appState.isRunning(project)
        let busy = appState.isBusy(project)

        return HStack(spacing: 12) {
            Button {
                appState.start(project)
            } label: {
                Label("Iniciar", systemImage: "play.fill")
            }
            .buttonStyle(ControlButtonStyle())
            .disabled(running || busy)

            Button {
                Task { await appState.restartProject(project) }
            } label: {
                if busy && running {
                    Label { Text("Reiniciando…") } icon: { ProgressView().controlSize(.small) }
                } else {
                    Label("Reiniciar", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(ControlButtonStyle())
            .disabled(!running || busy)
            .help("Detiene todas las instancias e inicia una sola, con el mismo perfil y puertos.")

            Button {
                Task { await appState.stopProject(project) }
            } label: {
                Label("Detener", systemImage: "stop.fill")
            }
            .buttonStyle(ControlButtonStyle(isDestructive: true))
            .disabled(!running || busy)
            .help("Detiene todas las instancias del proyecto.")
        }
    }

    // MARK: - Opciones de inicio, abrir y copiar

    private func startOptions(newest: RunningProcess?) -> some View {
        // Bindings "calculados": leen y escriben en AppState (como una propiedad con get/set en C#).
        let profileBinding = Binding<String>(
            get: { appState.selectedProfile(for: project) ?? "" },
            set: { appState.setSelectedProfile($0, for: project) }
        )
        let secretsBinding = Binding<Bool>(
            get: { appState.withSecrets(for: project) },
            set: { appState.setWithSecrets($0, for: project) }
        )
        let url = newest.flatMap { appState.url(of: $0) }

        return HStack(spacing: 16) {
            if project.profiles.isEmpty {
                Text("Sin launchSettings.json: perfil por defecto.")
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
                .controlSize(.small)
                .fixedSize()
                .disabled(!project.hasUserSecrets)
                .help(project.hasUserSecrets
                      ? "Sin secretos: se inicia sin cargar los user-secrets del proyecto."
                      : "Este proyecto no usa user-secrets.")

            Spacer()

            Button {
                if let url { NSWorkspace.shared.open(url) }
            } label: {
                Label("Abrir", systemImage: "safari")
            }
            .disabled(url == nil)
            .help(url?.absoluteString ?? "El proyecto no está en ejecución")

            Button {
                if let url {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            } label: {
                Label("Copiar URL", systemImage: "link")
            }
            .disabled(url == nil)
        }
        .font(.callout)
    }

    // MARK: - Instancias

    private func instanceCards(_ instances: [RunningProcess]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(instances.count == 1 ? "Instancia" : "Instancias")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(instances) { process in
                    InstanceCard(
                        process: process,
                        isNewest: instances.count > 1 && process.id == instances.first?.id,
                        isSelected: selectedPid == process.pid
                    )
                    .onTapGesture { selectedPid = process.pid }
                }
            }
        }
    }

    // MARK: - Logs

    @ViewBuilder
    private func logs(_ instances: [RunningProcess]) -> some View {
        if let launch = displayedLaunch(instances) {
            LogView(launch: launch)
                .frame(minHeight: 220)
        } else if !instances.isEmpty {
            Text("Los logs solo están disponibles para las instancias iniciadas desde Debu.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Logs a mostrar: los de la instancia elegida si la inició Debu; si no, la última ejecución del proyecto.
    private func displayedLaunch(_ instances: [RunningProcess]) -> AppLaunch? {
        if let pid = selectedPid, let process = instances.first(where: { $0.pid == pid }) {
            return appState.launch(for: process)
        }
        return appState.launches(of: project).first
    }
}

/// Tarjeta de una instancia: puertos, origen, antigüedad y "Cerrar esta".
private struct InstanceCard: View {
    @Environment(AppState.self) private var appState
    let process: RunningProcess
    let isNewest: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.portsDescription(of: process))
                    .font(.callout.weight(.medium).monospacedDigit())
                HStack(spacing: 4) {
                    Text(appState.launch(for: process) != nil ? "Debu" : "Externa")
                    if let start = process.startDate {
                        Text("· hace \(Text(start, style: .relative))")
                    }
                    Text("· PID \(String(process.pid))")
                    if isNewest {
                        Text("más reciente")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.primary.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                }
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .help(process.commandLine)
            Spacer()
            if appState.stoppingPids.contains(process.pid) {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await appState.stop(process) }
                } label: {
                    Label {
                        Text("Cerrar esta")
                    } icon: {
                        Image(systemName: "xmark").foregroundStyle(.red)
                    }
                }
                .controlSize(.small)
                .help("Detiene solo esta instancia.")
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isSelected ? Color.primary.opacity(0.5) : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Botón grande de la barra de control: ícono arriba, texto abajo, todos del mismo tamaño.
/// Un `ButtonStyle` es como un ControlTemplate de WPF: define cómo se ve el botón en cada estado.
struct ControlButtonStyle: ButtonStyle {
    var isDestructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .labelStyle(VerticalLabelStyle())
            .font(.callout.weight(.medium))
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.05)))
            .overlay(shape.strokeBorder(isDestructive ? Color.red.opacity(0.45) : Color.primary.opacity(0.15), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(shape)
    }
}

private struct VerticalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.title2)
            configuration.title
        }
    }
}
