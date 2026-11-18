import SwiftUI
import AppKit

/// Ícono de la barra de menú: silueta de la palanca + cantidad de instancias .NET (RF-17).
/// Se dibuja como una sola imagen porque la barra de menú no muestra bien varias vistas juntas.
/// Normal: imagen "plantilla" (macOS la pinta blanca o negra según el tema). Con duplicados: roja.
/// La silueta (MenuBarIcon en Assets) se genera con design/generate-icons.swift.
struct MenuBarLabel: View {
    let count: Int
    let hasDuplicates: Bool

    var body: some View {
        Image(nsImage: Self.render(count: count, highlighted: hasDuplicates))
            .accessibilityLabel("\(count) instancias .NET")
    }

    private static func render(count: Int, highlighted: Bool) -> NSImage {
        let color: NSColor = highlighted ? .systemRed : .black
        let symbol = tinted(NSImage(named: "MenuBarIcon") ?? NSImage(), color)

        let text = NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ])
        let textSize = text.size()
        let spacing: CGFloat = 4
        let size = NSSize(width: symbol.size.width + spacing + textSize.width, height: 18)

        let image = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(x: 0, y: (size.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            text.draw(at: NSPoint(x: symbol.size.width + spacing, y: (size.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = !highlighted
        return image
    }

    /// Pinta las partes visibles de una imagen con un color (como aplicar una máscara).
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// Panel que se abre al hacer clic en el ícono (diseño "opción C"):
/// una fila por proyecto (favoritos y los que corren) con Iniciar, Reiniciar y Detener.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    // Acción del entorno para abrir ventanas por id (como un servicio de navegación).
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let projects = appState.menuProjects
        let loose = appState.looseDotnetInstances
        let total = appState.totalDotnetInstances

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Debu").font(.headline)
                Spacer()
                Text(total == 0 ? "Nada en ejecución" : total == 1 ? "1 en ejecución" : "\(total) en ejecución")
                    .font(.callout)
                    .foregroundStyle(appState.hasDuplicates ? Color.red : Color.secondary)
            }
            .padding(.bottom, 10)

            if projects.isEmpty && loose.isEmpty {
                Text("Marcá proyectos con la estrella para tenerlos siempre acá.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(projects) { project in
                            Divider()
                            MenuProjectRow(project: project)
                        }
                        // Instancias .NET que no pertenecen a ningún proyecto conocido: solo se pueden detener.
                        ForEach(loose) { process in
                            Divider()
                            MenuLooseRow(process: process)
                        }
                    }
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.bottom, 10)

            HStack(spacing: 14) {
                Button("Abrir Debu") {
                    openWindow(id: MainWindow.id)
                    NSApp.activate()  // trae la app al frente
                }
                Spacer()
                Button("Detener todas") {
                    confirmStopAll(count: total)
                }
                .foregroundStyle(.red)
                .disabled(total == 0)
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Configuración")
                Button {
                    NSApp.terminate(nil)  // pasa por la pregunta de salida del AppDelegate
                } label: {
                    Image(systemName: "power")
                }
                .help("Salir de Debu")
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { appState.isMenuOpen = true }
        .onDisappear { appState.isMenuOpen = false }
    }

    /// Criterio de diseño: confirmar antes de "Detener todas".
    private func confirmStopAll(count: Int) {
        let alert = NSAlert()
        alert.messageText = count == 1 ? "¿Detener la instancia .NET?" : "¿Detener las \(count) instancias .NET?"
        alert.informativeText = "Se detienen todas las instancias .NET en ejecución, iniciadas o no por Debu."
        alert.addButton(withTitle: "Detener todas")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await appState.stopAllDotnet() }
        }
    }
}

/// Fila de un proyecto: ícono, nombre, puertos o estado, y tres botones redondos.
private struct MenuProjectRow: View {
    @Environment(AppState.self) private var appState
    let project: DotnetProject

    var body: some View {
        let instances = appState.instances(of: project)
        let running = appState.isRunning(project)
        let busy = appState.isBusy(project)

        HStack(spacing: 10) {
            ProjectAvatar(project: project, size: 30, isRunning: running, hasDuplicates: instances.count > 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(running ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    if instances.count > 1 {
                        Text("×\(instances.count)").font(.callout).foregroundStyle(.red)
                    }
                }
                Text(subtitle(instances))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if busy {
                ProgressView().controlSize(.small).frame(width: 106)
            } else {
                CircleButton(systemImage: "play.fill", help: "Iniciar") {
                    appState.start(project)
                }
                .disabled(running)
                CircleButton(systemImage: "arrow.clockwise", help: "Reiniciar") {
                    Task { await appState.restartProject(project) }
                }
                .disabled(!running)
                CircleButton(systemImage: "stop.fill", help: "Detener", isDestructive: true) {
                    Task { await appState.stopProject(project) }
                }
                .disabled(!running)
            }
        }
        .padding(.vertical, 8)
    }

    private func subtitle(_ instances: [RunningProcess]) -> String {
        if !instances.isEmpty {
            return instances.flatMap(\.ports).map(String.init).joined(separator: " · ")
        }
        return appState.startingLaunches(of: project).isEmpty ? "Detenido" : "Iniciando…"
    }
}

/// Fila de una instancia .NET sin proyecto: solo se puede detener.
private struct MenuLooseRow: View {
    @Environment(AppState.self) private var appState
    let process: RunningProcess

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(process.displayName).font(.callout.weight(.medium)).lineLimit(1)
                Text(process.portsText + " · sin proyecto")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if appState.stoppingPids.contains(process.pid) {
                ProgressView().controlSize(.small)
            } else {
                CircleButton(systemImage: "stop.fill", help: "Detener", isDestructive: true) {
                    Task { await appState.stop(process) }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// Botón redondo de solo ícono; el nombre aparece al pasar el mouse.
private struct CircleButton: View {
    let systemImage: String
    let help: String
    var isDestructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .overlay(Circle().strokeBorder(isDestructive ? Color.red.opacity(0.45) : Color.primary.opacity(0.18)))
                .opacity(isEnabled ? 1 : 0.3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
