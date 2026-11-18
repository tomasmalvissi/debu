import Foundation
import CoreServices

/// Vigila carpetas con FSEvents (el sistema de avisos de cambios de archivos de macOS),
/// como un `FileSystemWatcher` de .NET, pero para árboles de carpetas completos y con bajo costo.
/// Avisa con las rutas que cambiaron; los cambios que llegan juntos (por ejemplo, al cambiar de rama)
/// se agrupan en un solo aviso gracias a la latencia del stream.
nonisolated final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "Debu.FolderWatcher")
    private let onChange: @Sendable ([String]) -> Void

    init(onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Empieza a vigilar `paths` (reemplaza lo que se vigilaba antes).
    func watch(_ paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        // Función C que llama macOS. No puede capturar variables: recupera el FolderWatcher desde `info`.
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            watcher.onChange(Array(paths.prefix(count)))
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes   // rutas como CFArray de strings
            | kFSEventStreamCreateFlagFileEvents // un aviso por archivo, no solo por carpeta
            | kFSEventStreamCreateFlagWatchRoot  // avisar también si se mueve o borra la carpeta raíz
        )
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // segundos de latencia: agrupa ráfagas de cambios
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// ¿El cambio puede alterar la lista de proyectos o sus perfiles?
    /// Solo cuentan `.csproj`, `launchSettings.json` y los íconos de wwwroot, fuera de bin/obj/node_modules/.git.
    /// También cuenta una carpeta de proyecto conocida (por si se borró o se renombró entera).
    static func isRelevant(_ path: String, knownProjectDirectories: Set<String>) -> Bool {
        let ignored = ["/bin/", "/obj/", "/node_modules/", "/.git/"]
        guard !ignored.contains(where: path.contains) else { return false }
        if path.hasSuffix(".csproj") || path.hasSuffix("/Properties/launchSettings.json") { return true }
        if path.contains("/wwwroot/") && (path.hasSuffix("favicon.png") || path.hasSuffix("icon-192.png") || path.hasSuffix("favicon.ico")) {
            return true
        }
        return knownProjectDirectories.contains(path)
    }
}
