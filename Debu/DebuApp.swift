import SwiftUI

// Punto de entrada de la app (equivalente a Program.cs / Main en .NET).
@main
struct DebuApp: App {
    // Conecta el AppDelegate de AppKit con la app SwiftUI (arranque y salida).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // La instancia compartida de AppState. `@State` la mantiene viva mientras corre la app.
    @State private var appState = AppState.shared

    var body: some Scene {
        // `Window` (en lugar de WindowGroup) permite una sola ventana principal:
        // "Abrir ventana principal" la trae al frente en vez de abrir otra.
        Window("Debu", id: MainWindow.id) {
            ContentView()
                // Se inyecta en el entorno para que cualquier vista lo pida (como inyección de dependencias).
                .environment(appState)
        }
        .defaultSize(width: 1100, height: 680)

        // RF-17: ícono en la barra de menú con la cantidad de instancias .NET.
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel(count: appState.totalDotnetInstances, hasDuplicates: appState.hasDuplicates)
        }
        // `.window` muestra un panel con vistas SwiftUI (botones por fila) en lugar de un menú clásico.
        .menuBarExtraStyle(.window)

        // Ventana de Configuración: macOS la abre desde Debu > Settings… (⌘,).
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

enum MainWindow {
    static let id = "main"
}
