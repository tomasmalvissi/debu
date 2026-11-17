import SwiftUI
import UniformTypeIdentifiers  // define `.folder` (tipos de archivo), como un `using` de un namespace

/// Ventana de Configuración (Debu > Settings…, ⌘,).
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedFolders: Set<String> = []
    @State private var isPickingFolder = false

    /// Estado del inicio automático. Se lee de macOS al abrir la ventana: el usuario también puede cambiarlo
    /// desde Ajustes del Sistema.
    @State private var loginItemState = LoginItem.state
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("General") {
                Toggle("Abrir Debu al iniciar sesión", isOn: Binding(
                    get: { loginItemState != .disabled },
                    set: { setLoginItem($0) }
                ))
                if loginItemState == .requiresApproval {
                    HStack {
                        Label("macOS pide aprobarlo en Ítems de inicio.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Abrir Ajustes del Sistema") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginItemError {
                    Label(loginItemError, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
            }

            Section {
                TextField("Ruta", text: $appState.dotnetPathSetting,
                          prompt: Text("Automática (\(DotnetLocator.candidates.joined(separator: " o ")))"))
                if let path = appState.resolvedDotnetPath {
                    Label("Se usa \(path)", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("No se encontró dotnet en esa ruta.", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Ejecutable dotnet")
            } footer: {
                Text("Dejala vacía para buscarlo en las ubicaciones habituales.")
                    .foregroundStyle(.secondary)
            }

            Section {
                List(appState.rootFolders, id: \.self, selection: $selectedFolders) { folder in
                    folderRow(folder)
                }
                .frame(minHeight: 140)
                .overlay {
                    if appState.rootFolders.isEmpty {
                        Text("Agregá la carpeta donde tenés tus proyectos, por ejemplo ~/Projects.")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button {
                        isPickingFolder = true
                    } label: {
                        Label("Agregar carpeta…", systemImage: "plus")
                    }
                    Button {
                        let toRemove = selectedFolders
                        selectedFolders = []
                        Task { await appState.removeRootFolders(toRemove) }
                    } label: {
                        Label("Quitar", systemImage: "minus")
                    }
                    .disabled(selectedFolders.isEmpty)

                    Spacer()

                    if appState.isScanning {
                        ProgressView().controlSize(.small)
                    }
                    Text("\(appState.projects.count) proyectos web")
                        .foregroundStyle(.secondary)
                    Button("Buscar de nuevo") {
                        Task { await appState.scanProjects() }
                    }
                    .disabled(appState.isScanning)
                }
            } header: {
                Text("Carpetas raíz")
            } footer: {
                Text("Se buscan proyectos web .NET de forma recursiva. Se omiten bin, obj, node_modules y las carpetas ocultas.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580)
        .padding()
        .onAppear { loginItemState = LoginItem.state }
        // Selector de carpetas del sistema (como un FolderBrowserDialog).
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await appState.addRootFolders(urls) }
            }
        }
    }

    /// Fila de carpeta raíz. Si la carpeta ya no existe (se movió o se borró), lo indica.
    @ViewBuilder
    private func folderRow(_ folder: String) -> some View {
        let exists = FileManager.default.fileExists(atPath: folder)
        HStack {
            Label(folder, systemImage: exists ? "folder" : "folder.badge.questionmark")
                .lineLimit(1)
                .truncationMode(.head)
            if !exists {
                Spacer()
                Text("No existe").foregroundStyle(.red)
            }
        }
        .help(exists ? folder : "La carpeta no existe. Quitala o volvé a agregarla.")
    }

    private func setLoginItem(_ enabled: Bool) {
        loginItemError = nil
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            loginItemError = "No se pudo cambiar: \(error.localizedDescription)"
        }
        loginItemState = LoginItem.state
    }
}
