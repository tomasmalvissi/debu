import Foundation
import Observation

/// Estado observable de la app.
/// `@Observable` cumple el papel de `INotifyPropertyChanged`: cuando cambia una propiedad,
/// SwiftUI vuelve a dibujar solo las vistas que la leen. No hace falta disparar eventos a mano.
@Observable
final class AppState {

    /// Única instancia: la comparten la ventana principal, la barra de menú y el AppDelegate
    /// (como un singleton registrado en DI).
    static let shared = AppState()

    // MARK: - Procesos en escucha (RF-01, RF-05)

    /// Todos los procesos en escucha encontrados en el último refresco.
    private(set) var processes: [RunningProcess] = []

    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    /// Regla de refresco: cada 3 segundos con la ventana o el menú visibles; cada 10 en segundo plano.
    var isMainWindowVisible = false {
        didSet { if isMainWindowVisible && !oldValue { Task { await refresh() } } }
    }
    var isMenuOpen = false {
        didSet { if isMenuOpen && !oldValue { Task { await refresh() } } }
    }
    var refreshInterval: Duration {
        isMainWindowVisible || isMenuOpen ? .seconds(3) : .seconds(10)
    }

    private var backgroundWorkStarted = false

    /// Arranca al abrir la app y sigue aunque se cierre la ventana: la barra de menú necesita el contador.
    func startBackgroundWork() {
        guard !backgroundWorkStarted else { return }
        backgroundWorkStarted = true
        Task {
            await scanProjects()
            await runAutoRefresh()
        }
    }

    /// Lee los puertos y los datos de cada proceso. Los comandos corren fuera del hilo principal.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let sockets = try await PortScanner.scan()
            let details = try await ProcessInspector.inspect(sockets.map(\.pid))

            processes = sockets.compactMap { socket in
                // Si el proceso terminó entre las dos consultas, no tiene detalles: se omite.
                guard let info = details[socket.pid] else { return nil }
                return RunningProcess(
                    pid: socket.pid,
                    ports: socket.ports,
                    parentPid: info.parentPid,
                    startDate: info.startDate,
                    commandLine: info.commandLine,
                    workingDirectory: info.workingDirectory
                )
            }
            rematch()
            lastUpdated = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Refresca en bucle mientras corre la app.
    /// Espera de a medio segundo para que un cambio de intervalo (abrir la ventana) se note enseguida.
    /// Equivale a un `while (!token.IsCancellationRequested) { ...; await Task.Delay(...) }`.
    func runAutoRefresh() async {
        while !Task.isCancelled {
            await refresh()
            let started = ContinuousClock.now
            while !Task.isCancelled, ContinuousClock.now - started < refreshInterval {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Proyectos (RF-11, RF-16)

    /// Carpetas raíz donde se buscan proyectos. Se guardan en UserDefaults (como un appsettings del usuario).
    private(set) var rootFolders: [String] = UserDefaults.standard.stringArray(forKey: Keys.rootFolders) ?? []

    /// Proyectos web encontrados en las carpetas raíz.
    private(set) var projects: [DotnetProject] = []
    private(set) var isScanning = false

    func addRootFolders(_ urls: [URL]) async {
        let newPaths = urls.map { $0.resolvingSymlinksInPath().path }.filter { !rootFolders.contains($0) }
        guard !newPaths.isEmpty else { return }
        rootFolders.append(contentsOf: newPaths)
        rootFolders.sort()
        UserDefaults.standard.set(rootFolders, forKey: Keys.rootFolders)
        await scanProjects()
    }

    func removeRootFolders(_ paths: Set<String>) async {
        rootFolders.removeAll { paths.contains($0) }
        UserDefaults.standard.set(rootFolders, forKey: Keys.rootFolders)
        await scanProjects()
    }

    /// Vuelve a recorrer las carpetas raíz.
    func scanProjects() async {
        isScanning = true
        defer { isScanning = false }
        projects = await ProjectDiscovery.discover(in: rootFolders)
        rematch()
    }

    // MARK: - Agrupación por proyecto (RF-02, RF-03, RF-04)

    /// Resultado de asociar procesos con proyectos. Se recalcula al refrescar o al buscar proyectos.
    private(set) var match = InstanceMatcher.Result()

    private func rematch() {
        match = InstanceMatcher.match(processes, projects: projects)
    }

    /// Instancias de un proyecto, de la más reciente a la más antigua.
    func instances(of project: DotnetProject) -> [RunningProcess] {
        match.instancesByProject[project.id] ?? []
    }

    /// Proyectos para la lista lateral: primero los que tienen instancias, después por nombre.
    var sortedProjects: [DotnetProject] {
        projects.sorted {
            let lhs = instances(of: $0).count, rhs = instances(of: $1).count
            if (lhs > 0) != (rhs > 0) { return lhs > 0 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Total de instancias .NET asociadas a proyectos o sueltas.
    var totalDotnetInstances: Int {
        match.instancesByProject.values.reduce(0) { $0 + $1.count } + match.unmatched.filter(\.isDotnet).count
    }

    // MARK: - Otros puertos (RF-06)

    /// RF-06: los procesos que no son .NET están ocultos por defecto.
    var showNonDotnet = false

    /// Procesos sin proyecto: .NET primero y después por nombre.
    var otherProcesses: [RunningProcess] {
        match.unmatched
            .filter { showNonDotnet || $0.isDotnet }
            .sorted {
                if $0.isDotnet != $1.isDotnet { return $0.isDotnet }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    /// Protocolo de cada puerto del proceso, por ejemplo "5001 (HTTPS)".
    func portsDescription(of process: RunningProcess) -> String {
        let project = match.projectByPid[process.pid]
        return process.ports.map { port in
            let scheme = InstanceMatcher.scheme(forPort: port, process: process, project: project) ?? "desconocido"
            return "\(port) (\(scheme))"
        }
        .joined(separator: ", ")
    }

    // MARK: - Detener (RF-07, RF-09)

    /// PIDs que se están deteniendo: la fila muestra un indicador y desactiva el botón.
    private(set) var stoppingPids: Set<Int32> = []

    /// Error de la última acción, para mostrar en una alerta.
    var actionError: String?

    func stop(_ process: RunningProcess) async {
        await stop([process])
    }

    /// RF-09: detener todas las instancias de un proyecto.
    func stopAll(of project: DotnetProject) async {
        await stop(instances(of: project))
    }

    /// RF-09: detener todas salvo la más reciente.
    func stopAllButNewest(of project: DotnetProject) async {
        await stop(Array(instances(of: project).dropFirst()))
    }

    /// Detiene varias instancias en paralelo (como `Task.WhenAll`) y junta los errores.
    private func stop(_ targets: [RunningProcess]) async {
        guard !targets.isEmpty else { return }
        stoppingPids.formUnion(targets.map(\.pid))
        defer { stoppingPids.subtract(targets.map(\.pid)) }

        let errors = await withTaskGroup(of: String?.self) { group in
            for process in targets {
                group.addTask {
                    do {
                        try await ProcessController.stop(pid: process.pid, expectedStart: process.startDate)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            var messages: [String] = []
            for await message in group {
                if let message { messages.append(message) }
            }
            return messages
        }

        if !errors.isEmpty {
            actionError = errors.joined(separator: "\n")
        }
        await refresh()
    }

    // MARK: - Inicio de proyectos (RF-12 a RF-16)

    /// Ejecuciones de `dotnet run` iniciadas por Debu (en curso y terminadas).
    private(set) var launches: [AppLaunch] = []

    /// Ruta de dotnet configurada en Settings. Vacía = detección automática.
    var dotnetPathSetting: String = UserDefaults.standard.string(forKey: Keys.dotnetPath) ?? "" {
        didSet { UserDefaults.standard.set(dotnetPathSetting, forKey: Keys.dotnetPath) }
    }

    var resolvedDotnetPath: String? {
        DotnetLocator.resolve(configured: dotnetPathSetting)
    }

    /// RF-16: último perfil usado por proyecto (clave: ruta del .csproj).
    private var lastProfileByProject: [String: String] =
        UserDefaults.standard.dictionary(forKey: Keys.lastProfiles) as? [String: String] ?? [:]

    /// Modo con o sin secretos elegido por proyecto (por defecto, con secretos).
    private var withSecretsByProject: [String: Bool] = [:]

    /// Proyecto que espera la respuesta al aviso de instancia existente (RF-14).
    var pendingReplaceProjectId: String?

    /// Perfil elegido: el último usado si sigue existiendo; si no, el primero (el que usa `dotnet run` por defecto).
    func selectedProfile(for project: DotnetProject) -> String? {
        if let last = lastProfileByProject[project.id], project.profiles.contains(where: { $0.name == last }) {
            return last
        }
        return project.profiles.first?.name
    }

    func setSelectedProfile(_ profile: String, for project: DotnetProject) {
        lastProfileByProject[project.id] = profile
        UserDefaults.standard.set(lastProfileByProject, forKey: Keys.lastProfiles)
    }

    func withSecrets(for project: DotnetProject) -> Bool {
        withSecretsByProject[project.id] ?? true
    }

    func setWithSecrets(_ value: Bool, for project: DotnetProject) {
        withSecretsByProject[project.id] = value
    }

    /// Ejecuciones de un proyecto, la más reciente primero.
    func launches(of project: DotnetProject) -> [AppLaunch] {
        launches.filter { $0.projectId == project.id }.reversed()
    }

    /// Ejecución de Debu a la que pertenece una instancia: el proceso es el `dotnet run` o su hijo.
    func launch(for process: RunningProcess) -> AppLaunch? {
        launches.first { $0.isRunning && ($0.pid == process.pid || $0.pid == process.parentPid) }
    }

    /// Ejecuciones en curso que todavía no escuchan en un puerto (compilando o arrancando).
    func startingLaunches(of project: DotnetProject) -> [AppLaunch] {
        let instancePids = Set(instances(of: project).flatMap { [$0.pid, $0.parentPid] })
        return launches(of: project).filter { $0.isRunning && !instancePids.contains($0.pid) }
    }

    var runningLaunches: [AppLaunch] {
        launches.filter(\.isRunning)
    }

    /// Botón Iniciar. RF-14: si ya hay una instancia (o una arrancando), avisa en lugar de iniciar otra.
    func start(_ project: DotnetProject) {
        if !instances(of: project).isEmpty || !startingLaunches(of: project).isEmpty {
            pendingReplaceProjectId = project.id
            return
        }
        launch(project)
    }

    /// Respuesta "Reemplazar" al aviso: detiene lo que haya y después inicia.
    func replaceAndStart(_ project: DotnetProject) async {
        pendingReplaceProjectId = nil
        let starting = startingLaunches(of: project)
        await stopAll(of: project)
        for launch in starting {
            _ = try? await ProcessController.stop(pid: launch.pid, expectedStart: nil)
        }
        launch(project)
    }

    /// Inicia con lo elegido en el panel Iniciar.
    private func launch(_ project: DotnetProject) {
        launch(project, plan: StartPlan(
            profile: selectedProfile(for: project),
            withSecrets: withSecrets(for: project) || !project.hasUserSecrets,
            urls: []
        ))
    }

    private func launch(_ project: DotnetProject, plan: StartPlan) {
        guard let dotnetPath = resolvedDotnetPath else {
            actionError = ProcessController.StartError.dotnetNotFound.localizedDescription
            return
        }
        let launch = AppLaunch(project: project, profile: plan.profile, withSecrets: plan.withSecrets, urls: plan.urls)

        do {
            // AppLaunch pertenece al hilo principal: la salida llega en otro hilo y se pasa con `Task { @MainActor in }`
            // (como Dispatcher.Invoke en WPF).
            let process = try ProcessController.start(
                project: project,
                profile: plan.profile,
                withSecrets: plan.withSecrets,
                urls: plan.urls,
                dotnetPath: dotnetPath,
                onOutput: { text in Task { @MainActor in launch.append(text) } },
                onExit: { code in Task { @MainActor in launch.finish(exitCode: code) } }
            )
            launch.pid = process.processIdentifier
            launch.process = process
            launches.append(launch)
        } catch {
            actionError = "No se pudo iniciar \(project.name): \(error.localizedDescription)"
        }
    }

    // MARK: - Reiniciar (RF-08)

    /// Parámetros de inicio de una ejecución.
    struct StartPlan {
        var profile: String?
        var withSecrets: Bool
        /// URLs explícitas (`--urls`). Vacío = las del perfil.
        var urls: [String]
    }

    /// PIDs que se están reiniciando.
    private(set) var restartingPids: Set<Int32> = []

    /// Detiene la instancia y la vuelve a iniciar con el mismo proyecto, perfil y puertos.
    func restart(_ process: RunningProcess) async {
        guard let project = match.projectByPid[process.pid] else {
            actionError = "No se puede reiniciar: el proceso no está asociado a ningún proyecto."
            return
        }
        restartingPids.insert(process.pid)
        defer { restartingPids.remove(process.pid) }

        // El plan se arma antes de detener: después ya no existe la línea de comandos.
        let plan: StartPlan
        if let launch = launch(for: process) {
            plan = StartPlan(profile: launch.profile, withSecrets: launch.withSecrets, urls: launch.urls)
        } else {
            plan = await externalRestartPlan(for: process, project: project)
        }

        do {
            try await ProcessController.stop(pid: process.pid, expectedStart: process.startDate)
        } catch {
            actionError = error.localizedDescription
            return
        }
        launch(project, plan: plan)
        await refresh()
    }

    /// Recupera de la línea de comandos (del proceso y de su `dotnet run` / `dotnet watch`) el perfil y las URLs.
    /// Limitaciones conocidas: si no se pueden recuperar se usa el perfil por defecto; los secretos se cargan.
    private func externalRestartPlan(for process: RunningProcess, project: DotnetProject) async -> StartPlan {
        var commandLines = [process.commandLine]
        if let snapshot = try? await ProcessSnapshot.capture() {
            var pid = process.parentPid
            while pid > 1, let command = snapshot.commandLine[pid], ProcessController.isDotnetLauncher(command) {
                commandLines.append(command)
                pid = snapshot.parentPid[pid] ?? 1
            }
        }

        func argument(_ name: String) -> String? {
            for line in commandLines {
                let tokens = line.split(separator: " ").map(String.init)
                if let index = tokens.firstIndex(of: name), index + 1 < tokens.count { return tokens[index + 1] }
            }
            return nil
        }

        let recoveredProfile = argument("--launch-profile").flatMap { name in
            project.profiles.contains { $0.name == name } ? name : nil
        }
        let profile = recoveredProfile ?? project.profiles.first?.name
        let profilePorts = Set(project.profiles.first { $0.name == profile }?.applicationUrls.compactMap(\.port) ?? [])

        // Mismo puerto: se usan las --urls originales; si no hay y el perfil no cubre los puertos observados,
        // se arman a partir de los puertos en los que escuchaba.
        var urls: [String] = []
        if let original = argument("--urls") {
            urls = original.split(separator: ";").map(String.init)
        } else if !Set(process.ports).isSubset(of: profilePorts) {
            urls = process.ports.map { port in
                let scheme = InstanceMatcher.scheme(forPort: port, process: process, project: project)?.lowercased() ?? "http"
                return "\(scheme)://localhost:\(port)"
            }
        }
        return StartPlan(profile: profile, withSecrets: true, urls: urls)
    }

    // MARK: - URL de una instancia (RF-10)

    /// URL para abrir o copiar: la HTTPS si existe, si no la primera HTTP.
    func url(of process: RunningProcess) -> URL? {
        let project = match.projectByPid[process.pid]
        let candidates = process.ports.map { port in
            (port, InstanceMatcher.scheme(forPort: port, process: process, project: project)?.lowercased() ?? "http")
        }
        guard let chosen = candidates.first(where: { $0.1 == "https" }) ?? candidates.first else { return nil }
        return URL(string: "\(chosen.1)://localhost:\(chosen.0)")
    }

    // MARK: - Barra de menú (RF-17)

    /// Hay algún proyecto con más de una instancia.
    var hasDuplicates: Bool {
        match.instancesByProject.values.contains { $0.count > 1 }
    }

    /// Instancias .NET para la lista compacta: (nombre del proyecto, proceso), agrupadas por proyecto.
    var allDotnetInstances: [(name: String, process: RunningProcess, isDuplicate: Bool)] {
        let grouped = sortedProjects.flatMap { project in
            let list = instances(of: project)
            return list.map { (name: project.name, process: $0, isDuplicate: list.count > 1) }
        }
        let loose = match.unmatched.filter(\.isDotnet).map { (name: $0.displayName, process: $0, isDuplicate: false) }
        return grouped + loose
    }

    /// "Detener todas": todas las instancias .NET y las ejecuciones de Debu que aún arrancan.
    func stopAllDotnet() async {
        await stop(allDotnetInstances.map(\.process))
        await stopAllLaunches()
        await refresh()
    }

    /// Detiene todas las ejecuciones en curso de Debu (al salir de la app).
    func stopAllLaunches() async {
        await withTaskGroup(of: Void.self) { group in
            for launch in runningLaunches {
                let pid = launch.pid
                group.addTask { _ = try? await ProcessController.stop(pid: pid, expectedStart: nil) }
            }
        }
    }

    // MARK: - Claves de UserDefaults

    private enum Keys {
        static let rootFolders = "rootFolders"
        static let dotnetPath = "dotnetPath"
        static let lastProfiles = "lastProfileByProject"
    }
}
