import SwiftUI

/// Ventana principal: lista de proyectos a la izquierda y detalle a la derecha.
struct ContentView: View {
    // Toma el AppState inyectado en DebuApp (como un @inject en Blazor).
    @Environment(AppState.self) private var appState

    @State private var selection: SidebarItem?

    var body: some View {
        // NavigationSplitView: el diseño de dos paneles estándar de macOS (como Finder o Mail).
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(appState.isRefreshing)
            }
        }
        // Alerta con el error de la última acción.
        .alert(
            "No se pudo completar la acción",
            isPresented: Binding(
                get: { appState.actionError != nil },
                set: { if !$0 { appState.actionError = nil } }
            )
        ) {
            Button("Aceptar") {}
        } message: {
            Text(appState.actionError ?? "")
        }
        // El refresco corre a nivel de app (AppState.startBackgroundWork); la ventana solo avisa si está visible
        // para refrescar cada 3 segundos en lugar de 10.
        .onAppear { appState.isMainWindowVisible = true }
        .onDisappear { appState.isMainWindowVisible = false }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .project(let id):
            if let project = appState.projects.first(where: { $0.id == id }) {
                ProjectDetailView(project: project)
            } else {
                placeholder
            }
        case .otherPorts:
            OtherPortsView()
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Elegí un proyecto",
            systemImage: "sidebar.left",
            description: Text("\(appState.totalDotnetInstances) instancias .NET en ejecución.")
        )
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
