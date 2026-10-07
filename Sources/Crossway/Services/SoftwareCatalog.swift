import Foundation

/// Something Crossway knows how to install into a bottle (like CrossOver's "CrossTie" recipes).
struct CatalogItem: Identifiable, Hashable {
    enum Source: Hashable {
        /// Download an installer and run it in the bottle.
        case installer(url: URL, fileName: String, arguments: [String])
        /// Install components with winetricks.
        case winetricks([String])
    }

    let id: String
    let name: String
    let summary: String
    let symbol: String
    let category: Category
    let source: Source
    /// Windows paths of the main program, pinned automatically after installation.
    var mainProgram: [String] = []
    var tips: String?

    enum Category: String, CaseIterable, Identifiable {
        case stores = "Sklepy i launchery"
        case runtimes = "Biblioteki i komponenty"
        var id: String { rawValue }
    }

    static let all: [CatalogItem] = [
        CatalogItem(
            id: "steam", name: "Steam",
            summary: "Sklep i biblioteka gier Valve.",
            symbol: "gamecontroller.fill", category: .stores,
            source: .installer(url: URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!, fileName: "SteamSetup.exe", arguments: []),
            mainProgram: [#"C:\Program Files (x86)\Steam\steam.exe"#, #"C:\Program Files\Steam\steam.exe"#],
            tips: "Wymaga butelki z Wine Staging 11 — na GPTK (Wine 7.7) przeglądarka Steama się wysypuje i okno się nie pojawia. Gry DX9–11 uruchamiaj wtedy przez DXVK."
        ),
        CatalogItem(
            id: "epic", name: "Epic Games Launcher",
            summary: "Sklep Epic Games z darmowymi grami co tydzień.",
            symbol: "bag.fill", category: .stores,
            source: .installer(url: URL(string: "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi")!, fileName: "EpicGamesLauncherInstaller.msi", arguments: []),
            mainProgram: [#"C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"#, #"C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe"#],
            tips: "Gdy launcher nie startuje, dodaj argument -opengl lub -SkipBuildPatchPrereq."
        ),
        CatalogItem(
            id: "gog", name: "GOG Galaxy",
            summary: "Gry bez DRM z GOG.com.",
            symbol: "sparkles", category: .stores,
            source: .installer(url: URL(string: "https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe")!, fileName: "GOG_Galaxy_2.0.exe", arguments: []),
            mainProgram: [#"C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe"#]
        ),
        CatalogItem(
            id: "battlenet", name: "Battle.net",
            summary: "Diablo, Overwatch, World of Warcraft, Call of Duty.",
            symbol: "bolt.fill", category: .stores,
            source: .installer(url: URL(string: "https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live")!, fileName: "Battle.net-Setup.exe", arguments: []),
            mainProgram: [#"C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe"#, #"C:\Program Files (x86)\Battle.net\Battle.net.exe"#]
        ),
        CatalogItem(
            id: "ea", name: "EA app",
            summary: "Gry Electronic Arts (następca Origin).",
            symbol: "e.circle.fill", category: .stores,
            source: .installer(url: URL(string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe")!, fileName: "EAappInstaller.exe", arguments: []),
            mainProgram: [#"C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EALauncher.exe"#]
        ),
        CatalogItem(
            id: "ubisoft", name: "Ubisoft Connect",
            summary: "Assassin's Creed, Far Cry i inne gry Ubisoftu.",
            symbol: "u.circle.fill", category: .stores,
            source: .installer(url: URL(string: "https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe")!, fileName: "UbisoftConnectInstaller.exe", arguments: []),
            mainProgram: [#"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe"#]
        ),
        CatalogItem(
            id: "rockstar", name: "Rockstar Games Launcher",
            summary: "GTA V, Red Dead Redemption 2.",
            symbol: "star.fill", category: .stores,
            source: .installer(url: URL(string: "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe")!, fileName: "Rockstar-Games-Launcher.exe", arguments: []),
            mainProgram: [#"C:\Program Files\Rockstar Games\Launcher\Launcher.exe"#]
        ),
        CatalogItem(
            id: "vcrun", name: "Visual C++ 2015–2022",
            summary: "Biblioteki wymagane przez większość współczesnych gier.",
            symbol: "shippingbox.fill", category: .runtimes, source: .winetricks(["vcrun2022"])
        ),
        CatalogItem(
            id: "d3dx", name: "DirectX (d3dx9, d3dcompiler_47)",
            summary: "Dodatkowe biblioteki DirectX dla starszych gier.",
            symbol: "cube.fill", category: .runtimes, source: .winetricks(["d3dx9", "d3dcompiler_47"])
        ),
        CatalogItem(
            id: "dotnet48", name: ".NET Framework 4.8",
            summary: "Wymagany przez część launcherów i narzędzi (instalacja trwa długo).",
            symbol: "gearshape.2.fill", category: .runtimes, source: .winetricks(["dotnet48"])
        ),
        CatalogItem(
            id: "xact", name: "XAudio / XACT",
            summary: "Naprawia brak dźwięku w części gier.",
            symbol: "speaker.wave.2.fill", category: .runtimes, source: .winetricks(["xact", "xact_x64"])
        ),
        CatalogItem(
            id: "corefonts", name: "Czcionki Microsoft",
            summary: "Arial, Times New Roman, Verdana… — poprawia wygląd tekstu.",
            symbol: "textformat", category: .runtimes, source: .winetricks(["corefonts"])
        ),
    ]
}

/// Runs catalog installs and winetricks, exposing a live log to the UI.
@MainActor
final class InstallManager: ObservableObject {
    struct Job: Identifiable {
        let id = UUID()
        let bottleID: UUID
        let title: String
        var status: String
        var fraction: Double?
        var finished = false
        var failed = false
        var output = ""
    }

    @Published private(set) var jobs: [Job] = []

    private let bottles: BottleManager
    private let runtimes: RuntimeManager
    private var runner: WineRunner { bottles.runner }

    init(bottles: BottleManager, runtimes: RuntimeManager) {
        self.bottles = bottles
        self.runtimes = runtimes
    }

    func jobs(for bottle: Bottle) -> [Job] { jobs.filter { $0.bottleID == bottle.id } }

    func clearFinished() { jobs.removeAll { $0.finished } }

    func install(_ item: CatalogItem, in bottle: Bottle) {
        let job = Job(bottleID: bottle.id, title: item.name, status: "Przygotowanie…")
        jobs.append(job)
        Task {
            do {
                let runtime = try bottles.runtime(for: bottle)
                switch item.source {
                case let .installer(url, fileName, arguments):
                    let file = Paths.downloads.appendingPathComponent(fileName)
                    update(job.id) { $0.status = "Pobieranie \(fileName)…" }
                    _ = try await Downloader.download(url, to: file) { fraction, written, total in
                        Task { @MainActor [weak self] in
                            self?.update(job.id) {
                                $0.fraction = fraction
                                $0.status = "Pobieranie — \(written.formattedBytes)" + (total > 0 ? " z \(total.formattedBytes)" : "")
                            }
                        }
                    }
                    try await runInstaller(file, arguments: arguments, jobID: job.id, bottle: bottle, runtime: runtime)
                    pinMainProgram(item, in: bottle)
                case let .winetricks(verbs):
                    try await runWinetricks(verbs, jobID: job.id, bottle: bottle, runtime: runtime)
                }
                update(job.id) { $0.status = "Zainstalowano"; $0.finished = true; $0.fraction = 1 }
            } catch {
                update(job.id) { $0.status = error.localizedDescription; $0.finished = true; $0.failed = true }
            }
        }
    }

    /// Runs an arbitrary installer (.exe/.msi) the user picked.
    func installFile(_ file: URL, in bottle: Bottle) {
        let job = Job(bottleID: bottle.id, title: file.lastPathComponent, status: "Uruchamianie instalatora…")
        jobs.append(job)
        Task {
            do {
                let runtime = try bottles.runtime(for: bottle)
                try await runInstaller(file, arguments: [], jobID: job.id, bottle: bottle, runtime: runtime)
                update(job.id) { $0.status = "Instalator zakończył pracę"; $0.finished = true; $0.fraction = 1 }
            } catch {
                update(job.id) { $0.status = error.localizedDescription; $0.finished = true; $0.failed = true }
            }
        }
    }

    func runWinetricks(verbs: [String], in bottle: Bottle) {
        let job = Job(bottleID: bottle.id, title: "winetricks " + verbs.joined(separator: " "), status: "Przygotowanie…")
        jobs.append(job)
        Task {
            do {
                let runtime = try bottles.runtime(for: bottle)
                try await runWinetricks(verbs, jobID: job.id, bottle: bottle, runtime: runtime)
                update(job.id) { $0.status = "Gotowe"; $0.finished = true; $0.fraction = 1 }
            } catch {
                update(job.id) { $0.status = error.localizedDescription; $0.finished = true; $0.failed = true }
            }
        }
    }

    private func runInstaller(_ file: URL, arguments: [String], jobID: UUID, bottle: Bottle, runtime: WineRuntime) async throws {
        update(jobID) { $0.status = "Instalator działa — dokończ instalację w jego oknie…"; $0.fraction = nil }
        let args = WineLauncher.wineArguments(forFile: file, extraArguments: arguments)
        let code = try await runner.runAndWait(args, name: "install-" + file.deletingPathExtension().lastPathComponent,
                                               workingDirectory: file.deletingLastPathComponent(), in: bottle, runtime: runtime)
        // Many installers spawn the real setup and exit immediately — wait for the bottle to go idle.
        update(jobID) { $0.status = "Czekam, aż instalator zakończy wszystkie procesy…" }
        await runner.waitForWineserver(in: bottle, runtime: runtime)
        if code != 0 && code != 1 {
            // Exit code 1 is common for installers that relaunch themselves; treat as success.
            update(jobID) { $0.output += "Instalator zwrócił kod \(code).\n" }
        }
    }

    private func pinMainProgram(_ item: CatalogItem, in bottle: Bottle) {
        guard let current = bottles.bottle(id: bottle.id) else { return }
        for path in item.mainProgram {
            let url = current.unixPath(forWindowsPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                bottles.pin(PinnedProgram(name: item.name, path: url.path), in: current)
                return
            }
        }
    }

    private func runWinetricks(_ verbs: [String], jobID: UUID, bottle: Bottle, runtime: WineRuntime) async throws {
        if !runtimes.winetricksInstalled {
            update(jobID) { $0.status = "Pobieranie winetricks…" }
            await runtimes.installWinetricks()
            guard runtimes.winetricksInstalled else { throw CrosswayError.message("Nie udało się pobrać winetricks.") }
        }
        guard Paths.cabextractPath != nil else {
            throw CrosswayError.message("winetricks potrzebuje programu cabextract. Zainstaluj go poleceniem: brew install cabextract")
        }
        update(jobID) { $0.status = "winetricks: \(verbs.joined(separator: ", ")) — to może potrwać kilka minut…"; $0.fraction = nil }

        var env = WineLauncher.environment(bottle: bottle, runtime: runtime)
        env["WINE"] = runtime.wineBinary.lastPathComponent
        env["W_OPT_UNATTENDED"] = "1"
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        // winetricks wants plain overrides; keep winemenubuilder off.
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"

        let logURL = WineLauncher.newLogURL(bottle: bottle, label: "winetricks-" + verbs.joined(separator: "-"))
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Paths.winetricks.path, "-q"] + verbs
        process.environment = env
        process.currentDirectoryURL = bottle.url
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            log.write(data)
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.update(jobID) {
                    $0.output += text
                    if $0.output.count > 60_000 { $0.output = String($0.output.suffix(40_000)) }
                    if let line = text.split(separator: "\n").last(where: { $0.hasPrefix("Executing") || $0.contains("Downloading") }) {
                        $0.status = String(line.prefix(140))
                    }
                }
            }
        }
        try process.run()
        let code = await WineRunner.waitForExit(process)
        pipe.fileHandleForReading.readabilityHandler = nil
        try? log.close()
        await runner.waitForWineserver(in: bottle, runtime: runtime)
        if code != 0 { throw CrosswayError.processFailed("winetricks", code) }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
}
