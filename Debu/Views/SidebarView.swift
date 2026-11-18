import SwiftUI

/// Elemento seleccionable de la lista lateral.
/// Un `enum` con datos asociados es como una jerarquía cerrada de records en C# (`abstract record` + subclases).
enum SidebarItem: Hashable {
    case project(String)  // id del proyecto (ruta del .csproj)
    case otherPorts
}

/// Panel izquierdo: proyectos detectados con su estado y "Otros puertos".
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Proyectos") {
                if appState.projects.isEmpty {
                    emptyProjects
                }
                ForEach(appState.sortedProjects) { project in
                    ProjectRow(project: project, count: appState.instances(of: project).count,
                               isFavorite: appState.isFavorite(project))
                        .tag(SidebarItem.project(project.id))
                }
            }
            Section {
                Label("Otros puertos", systemImage: "network")
                    .badge(appState.otherProcesses.count)
                    .tag(SidebarItem.otherPorts)
            }
        }
        .listStyle(.sidebar)
        // Pie fijo debajo de la lista (como un StatusStrip): estado del último refresco.
        .safeAreaInset(edge: .bottom) {
            statusFooter
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        HStack(spacing: 6) {
            if let error = appState.lastError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("Error al leer los puertos")
                    .help(error)
            } else if let updated = appState.lastUpdated {
                Text("Actualizado \(updated.formatted(date: .omitted, time: .standard))")
            } else {
                ProgressView().controlSize(.mini)
                Text("Leyendo puertos…")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var emptyProjects: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.isScanning {
                ProgressView("Buscando proyectos…").controlSize(.small)
            } else {
                Text(appState.rootFolders.isEmpty
                     ? "Configurá las carpetas donde están tus proyectos."
                     : "No se encontraron proyectos web en las carpetas configuradas.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // Abre la ventana de Configuración (Debu > Settings…).
                SettingsLink {
                    Label("Configurar carpetas…", systemImage: "folder.badge.plus")
                }
            }
        }
        .padding(.vertical, 4)
        .selectionDisabled()
    }
}

/// Fila de un proyecto: indicador de estado, nombre y contador.
private struct ProjectRow: View {
    let project: DotnetProject
    let count: Int
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .help(statusHelp)
            Text(project.name)
                .lineLimit(1)
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Favorito: aparece siempre en la barra de menú")
            }
            Spacer()
            if count > 1 {
                // RF-04: marca visual cuando hay más de una instancia.
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("Hay \(count) instancias de este proyecto")
            }
            if count > 0 {
                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(count > 1 ? .red : .secondary)
            }
        }
    }

    private var statusColor: Color {
        switch count {
        case 0: .gray.opacity(0.4)
        case 1: .primary
        default: .red
        }
    }

    private var statusHelp: String {
        switch count {
        case 0: "Sin instancias"
        case 1: "Una instancia"
        default: "Más de una instancia"
        }
    }
}
