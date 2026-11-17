import Foundation
import ServiceManagement

/// Abrir Debu al iniciar sesión (decisión del proyecto: opción en Configuración, desactivada por defecto).
/// `SMAppService.mainApp` registra la propia app en "Ítems de inicio" de Ajustes del Sistema.
enum LoginItem {

    enum State {
        case enabled
        case disabled
        /// macOS pide aprobarlo en Ajustes del Sistema > General > Ítems de inicio.
        case requiresApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    /// Activa o desactiva el inicio automático. Lanza un error si macOS lo rechaza.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Abre Ajustes del Sistema en la sección Ítems de inicio.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
