import SwiftUI
import AppKit

/// Ícono de la barra de menú: símbolo + cantidad de instancias .NET (RF-17).
/// Se dibuja como una sola imagen porque la barra de menú no muestra bien varias vistas juntas.
/// Normal: imagen "plantilla" (macOS la pinta blanca o negra según el tema). Con duplicados: naranja.
struct MenuBarLabel: View {
    let count: Int
    let hasDuplicates: Bool

    var body: some View {
        Image(nsImage: Self.render(count: count, highlighted: hasDuplicates))
            .accessibilityLabel("\(count) instancias .NET")
    }

    private static func render(count: Int, highlighted: Bool) -> NSImage {
        let color: NSColor = highlighted ? .systemOrange : .black
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let symbol = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) ?? NSImage()

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
}

/// Panel que se abre al hacer clic en el ícono: lista compacta y accesos rápidos.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    // Acción del entorno para abrir ventanas por id (como un servicio de navegación).
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let rows = appState.allDotnetInstances

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rows.count == 1 ? "1 instancia .NET" : "\(rows.count) instancias .NET")
                    .font(.headline)
                if appState.hasDuplicates {
                    Label("Hay proyectos con más de una instancia", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            if rows.isEmpty {
                Text("No hay instancias .NET en ejecución.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows, id: \.process.pid) { row in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(row.isDuplicate ? Color.orange : Color.green)
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.name).lineLimit(1)
                                    Text(appState.portsDescription(of: row.process))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StopButton(process: row.process)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button {
                    openWindow(id: MainWindow.id)
                    NSApp.activate()  // trae la app al frente
                } label: {
                    Label("Abrir ventana principal", systemImage: "macwindow")
                }
                Spacer()
                Button(role: .destructive) {
                    confirmStopAll(count: rows.count)
                } label: {
                    Label("Detener todas", systemImage: "stop.fill")
                }
                .disabled(rows.isEmpty)
            }

            HStack {
                SettingsLink {
                    Label("Configuración…", systemImage: "gearshape")
                }
                Spacer()
                Button {
                    NSApp.terminate(nil)  // pasa por la pregunta de salida del AppDelegate
                } label: {
                    Label("Salir", systemImage: "power")
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(14)
        .frame(width: 360)
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
