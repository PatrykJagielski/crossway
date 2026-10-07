import Foundation

/// A runtime or component that can be downloaded from GitHub releases.
struct DownloadOffer: Identifiable, Hashable {
    enum Kind { case runtime, sikarugir, dxvk }

    let id: String
    let title: String
    let summary: String
    let repository: String
    /// Regex matched against release asset names.
    let assetPattern: String
    let kind: Kind
    let recommended: Bool

    /// Sikarugir's "Template" wrapper ships the libraries and renderers its engines need.
    static let sikarugirTemplate = DownloadOffer(
        id: "sikarugir-template",
        title: "Sikarugir Template",
        summary: "",
        repository: "Sikarugir-App/Template",
        assetPattern: #"^Template-[0-9.]+\.tar\.xz$"#,
        kind: .sikarugir,
        recommended: false
    )

    static let all: [DownloadOffer] = [
        DownloadOffer(
            id: "sikarugir",
            title: "Wine 10 CrossOver + D3DMetal 4 (Sikarugir)",
            summary: "Wine z kodu CrossOver z rendererami D3DMetal 4, DXMT i DXVK do wyboru w każdej butelce. Działa z nowym Steamem — najlepszy wybór do gier.",
            repository: "Sikarugir-App/Engines",
            assetPattern: #"^WS12WineSikarugir10\.0(_[0-9]+)?\.tar\.xz$"#,
            kind: .sikarugir,
            recommended: true
        ),
        DownloadOffer(
            id: "gptk",
            title: "Game Porting Toolkit 3 (D3DMetal)",
            summary: "Wine 7.7 z D3DMetal 3 od Apple. Szybkie w grach, ale nowy klient Steama na nim nie działa — dla gier spoza Steama.",
            repository: "Gcenx/game-porting-toolkit",
            assetPattern: #"^game-porting-toolkit-.*\.tar\.xz$"#,
            kind: .runtime,
            recommended: false
        ),
        DownloadOffer(
            id: "wine-staging",
            title: "Wine Staging (najnowszy)",
            summary: "Najnowsze Wine z łatkami Staging. Lepsza zgodność launcherów i aplikacji, grafika przez WineD3D/DXVK (bez D3DMetal).",
            repository: "Gcenx/macOS_Wine_builds",
            assetPattern: #"^wine-staging-.*-osx64\.tar\.xz$"#,
            kind: .runtime,
            recommended: false
        ),
        DownloadOffer(
            id: "wine-devel",
            title: "Wine Devel (najnowszy)",
            summary: "Czyste, rozwojowe Wine z WineHQ. Przydatne do testów zgodności.",
            repository: "Gcenx/macOS_Wine_builds",
            assetPattern: #"^wine-devel-.*-osx64\.tar\.xz$"#,
            kind: .runtime,
            recommended: false
        ),
        DownloadOffer(
            id: "dxvk",
            title: "DXVK-macOS (async)",
            summary: "DirectX 9/10/11 → Vulkan → MoltenVK. Działa ze środowiskami z Vulkanem (Wine Staging/Devel, WhiskyWine) — nie z GPTK.",
            repository: "Gcenx/DXVK-macOS",
            // The "-repack" archives lack dxgi.dll/d3d9.dll, so take the full ones.
            assetPattern: #"^dxvk-macOS-async-v[0-9.]+-[0-9]+\.tar\.gz$"#,
            kind: .dxvk,
            recommended: false
        ),
    ]
}

struct ReleaseAsset {
    let tag: String
    let name: String
    let url: URL
    let size: Int64
}

/// Progress of a long-running download/install shown in the UI.
struct TaskProgress: Equatable {
    var message: String
    var fraction: Double?
}

@MainActor
final class RuntimeManager: ObservableObject {
    @Published private(set) var runtimes: [WineRuntime] = []
    @Published private(set) var progress: [String: TaskProgress] = [:]
    @Published var lastError: String?
    @Published private(set) var dxvkInstalled = false
    @Published private(set) var winetricksInstalled = false

    private let defaultRuntimeKey = "defaultRuntimeID"

    init() {
        Paths.ensureDirectories()
        refresh()
    }

    func refresh() {
        runtimes = RuntimeDiscovery.all()
        dxvkInstalled = FileManager.default.directoryExists(Paths.dxvk.appendingPathComponent("x64"))
        winetricksInstalled = FileManager.default.isExecutableFile(atPath: Paths.winetricks.path)
    }

    func runtime(id: String) -> WineRuntime? {
        runtimes.first { $0.id == id }
    }

    var defaultRuntime: WineRuntime? {
        if let id = UserDefaults.standard.string(forKey: defaultRuntimeKey), let runtime = runtime(id: id) {
            return runtime
        }
        // Prefer engines with D3DMetal *and* a modern Wine (Steam works), then any D3DMetal build.
        return runtimes.first { $0.hasD3DMetal && !$0.d3dMetalIsBuiltin && $0.source == .managed }
            ?? runtimes.first { $0.hasD3DMetal && $0.source == .managed }
            ?? runtimes.first { $0.hasD3DMetal }
            ?? runtimes.first
    }

    func setDefault(_ runtime: WineRuntime) {
        UserDefaults.standard.set(runtime.id, forKey: defaultRuntimeKey)
        objectWillChange.send()
    }

    func isInstalled(_ offer: DownloadOffer) -> Bool {
        switch offer.kind {
        case .dxvk: return dxvkInstalled
        case .runtime, .sikarugir: return runtimes.contains { $0.source == .managed && $0.id.hasPrefix(offer.id + "-") }
        }
    }

    // MARK: - Downloads

    func latestAsset(for offer: DownloadOffer) async throws -> ReleaseAsset {
        let api = URL(string: "https://api.github.com/repos/\(offer.repository)/releases?per_page=10")!
        var request = URLRequest(url: api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Crossway/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CrosswayError.message("Nie udało się odczytać listy wydań z GitHuba (\(offer.repository)).")
        }
        let regex = try NSRegularExpression(pattern: offer.assetPattern)
        for release in releases where (release["prerelease"] as? Bool) != true && (release["draft"] as? Bool) != true {
            let tag = release["tag_name"] as? String ?? "?"
            // Some repos (Sikarugir) keep every build in one release: take the newest upload.
            let matches = (release["assets"] as? [[String: Any]] ?? []).filter { asset in
                guard let name = asset["name"] as? String else { return false }
                return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
            }
            guard let asset = matches.max(by: { ($0["updated_at"] as? String ?? "") < ($1["updated_at"] as? String ?? "") }),
                  let name = asset["name"] as? String,
                  let link = asset["browser_download_url"] as? String,
                  let url = URL(string: link) else { continue }
            return ReleaseAsset(tag: tag, name: name, url: url, size: (asset["size"] as? NSNumber)?.int64Value ?? 0)
        }
        throw CrosswayError.message("Nie znaleziono pliku do pobrania w \(offer.repository).")
    }

    func install(_ offer: DownloadOffer) async {
        guard progress[offer.id] == nil else { return }
        progress[offer.id] = TaskProgress(message: "Sprawdzanie najnowszej wersji…", fraction: nil)
        defer { progress[offer.id] = nil; refresh() }
        do {
            let asset = try await latestAsset(for: offer)
            let archive = try await download(asset, offerID: offer.id)
            switch offer.kind {
            case .runtime: try await installRuntime(from: archive, offer: offer, asset: asset)
            case .sikarugir: try await installSikarugir(engine: archive, offer: offer, asset: asset)
            case .dxvk: try await installDXVK(from: archive)
            }
            try? FileManager.default.removeItem(at: archive)
        } catch is CancellationError {
        } catch {
            lastError = "\(offer.title): \(error.localizedDescription)"
        }
    }

    private func download(_ asset: ReleaseAsset, offerID: String) async throws -> URL {
        let destination = Paths.downloads.appendingPathComponent(asset.name)
        return try await Downloader.download(asset.url, to: destination) { fraction, written, total in
            Task { @MainActor [weak self] in
                let size = total > 0 ? "\(written.formattedBytes) z \(total.formattedBytes)" : written.formattedBytes
                self?.progress[offerID] = TaskProgress(message: "Pobieranie \(asset.tag) — \(size)", fraction: fraction)
            }
        }
    }

    private func installRuntime(from archive: URL, offer: DownloadOffer, asset: ReleaseAsset) async throws {
        progress[offer.id] = TaskProgress(message: "Rozpakowywanie…", fraction: nil)
        let fm = FileManager.default
        let safeTag = asset.tag.replacingOccurrences(of: "/", with: "-")
        let id = "\(offer.id)-\(safeTag)"
        let target = Paths.runtimes.appendingPathComponent(id, isDirectory: true)
        let staging = Paths.runtimes.appendingPathComponent(".staging-\(id)", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let (code, output) = try await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path])
        guard code == 0 else { throw CrosswayError.message("Rozpakowanie nie powiodło się: \(output.suffix(400))") }

        // Archives contain e.g. "Game Porting Toolkit.app/Contents/Resources/wine".
        guard let wineRoot = findWineRoot(in: staging) else {
            throw CrosswayError.message("Archiwum nie zawiera Wine (brak bin/wineserver).")
        }
        let relative = String(wineRoot.standardizedFileURL.path.dropFirst(staging.standardizedFileURL.path.count + 1))

        try? fm.removeItem(at: target)
        try fm.moveItem(at: staging, to: target)
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])

        progress[offer.id] = TaskProgress(message: "Sprawdzanie wersji Wine…", fraction: nil)
        let wineRootURL = target.appendingPathComponent(relative)
        let probe = WineRuntime(id: id, name: "", version: "", wineRoot: wineRootURL, source: .managed)
        var version = asset.tag
        var env = ProcessInfo.processInfo.environment
        env.merge(probe.baseEnvironment) { _, new in new }
        if let (status, out) = try? await Shell.run(probe.wineBinary.path, ["--version"], environment: env), status == 0 {
            version = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let name: String
        switch offer.id {
        case "gptk": name = "Game Porting Toolkit \(asset.tag.replacingOccurrences(of: "Game-Porting-Toolkit-", with: ""))"
        case "sikarugir": name = "Wine 10 CrossOver (\(asset.tag))"
        default: name = "\(offer.title.replacingOccurrences(of: " (najnowszy)", with: "")) \(asset.tag)"
        }
        let manifest = RuntimeManifest(id: id, name: name, version: version, wineRootRelative: relative, installed: Date())
        try JSONEncoder.crossway.encode(manifest).write(to: target.appendingPathComponent(RuntimeDiscovery.manifestName))
    }

    /// Sikarugir engine (`wswine.bundle`) + the Template's `Contents/Frameworks`
    /// (dylibs and the d3dmetal/dxmt/dxvk renderers) laid out side by side.
    private func installSikarugir(engine: URL, offer: DownloadOffer, asset: ReleaseAsset) async throws {
        let template = try await latestAsset(for: DownloadOffer.sikarugirTemplate)
        let templateArchive = try await download(template, offerID: offer.id)
        defer { try? FileManager.default.removeItem(at: templateArchive) }

        progress[offer.id] = TaskProgress(message: "Rozpakowywanie bibliotek i rendererów…", fraction: nil)
        let fm = FileManager.default
        let scratch = Paths.downloads.appendingPathComponent(".template-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let (code, output) = try await Shell.run("/usr/bin/tar", ["-xf", templateArchive.path, "-C", scratch.path])
        guard code == 0 else { throw CrosswayError.message("Rozpakowanie Template nie powiodło się: \(output.suffix(400))") }
        guard let app = try fm.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw CrosswayError.message("Archiwum Template nie zawiera aplikacji.")
        }
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        guard fm.directoryExists(frameworks.appendingPathComponent("renderer")) else {
            throw CrosswayError.message("Template nie zawiera rendererów (Frameworks/renderer).")
        }

        // Tag the runtime by engine build, e.g. sikarugir-WS12WineSikarugir10.0_8.
        let engineName = asset.name.replacingOccurrences(of: ".tar.xz", with: "")
        let tagged = ReleaseAsset(tag: engineName, name: asset.name, url: asset.url, size: asset.size)
        try await installRuntime(from: engine, offer: offer, asset: tagged)

        let target = Paths.runtimes.appendingPathComponent("\(offer.id)-\(engineName)")
        try? fm.removeItem(at: target.appendingPathComponent("Frameworks"))
        try fm.moveItem(at: frameworks, to: target.appendingPathComponent("Frameworks"))
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])

        // Re-probe now that the libraries are in place.
        if var manifest = try? JSONDecoder.crossway.decode(RuntimeManifest.self, from: Data(contentsOf: target.appendingPathComponent(RuntimeDiscovery.manifestName))) {
            let probe = WineRuntime(id: manifest.id, name: "", version: "", wineRoot: target.appendingPathComponent(manifest.wineRootRelative), source: .managed)
            var env = ProcessInfo.processInfo.environment
            env.merge(probe.baseEnvironment) { _, new in new }
            if let (status, out) = try? await Shell.run(probe.wineBinary.path, ["--version"], environment: env), status == 0 {
                manifest.version = out.trimmingCharacters(in: .whitespacesAndNewlines)
                manifest.name = "Wine 10 CrossOver (Sikarugir)"
                try JSONEncoder.crossway.encode(manifest).write(to: target.appendingPathComponent(RuntimeDiscovery.manifestName))
            }
        }
    }

    private func findWineRoot(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in enumerator {
            if enumerator.level > 6 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == "wineserver", url.deletingLastPathComponent().lastPathComponent == "bin" {
                return url.deletingLastPathComponent().deletingLastPathComponent()
            }
        }
        return nil
    }

    private func findDirectory(named name: String, in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    private func installDXVK(from archive: URL) async throws {
        progress["dxvk"] = TaskProgress(message: "Rozpakowywanie DXVK…", fraction: nil)
        let fm = FileManager.default
        let staging = Paths.components.appendingPathComponent(".staging-dxvk")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let (code, output) = try await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path])
        guard code == 0 else { throw CrosswayError.message("Rozpakowanie DXVK nie powiodło się: \(output.suffix(400))") }

        guard let root = findDirectory(named: "x64", in: staging)?.deletingLastPathComponent() else { throw CrosswayError.message("Archiwum DXVK nie zawiera katalogu x64.") }
        guard fm.fileExists(atPath: root.appendingPathComponent("x64/dxgi.dll").path) else {
            throw CrosswayError.message("Archiwum DXVK nie zawiera dxgi.dll.")
        }
        try? fm.removeItem(at: Paths.dxvk)
        try fm.moveItem(at: root, to: Paths.dxvk)
        try? fm.removeItem(at: staging)
    }

    func installWinetricks() async {
        progress["winetricks"] = TaskProgress(message: "Pobieranie winetricks…", fraction: nil)
        defer { progress["winetricks"] = nil; refresh() }
        do {
            let url = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")!
            _ = try await Downloader.download(url, to: Paths.winetricks) { _, _, _ in }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Paths.winetricks.path)
        } catch {
            lastError = "winetricks: \(error.localizedDescription)"
        }
    }

    func delete(_ runtime: WineRuntime) {
        guard runtime.source == .managed else { return }
        let folder = Paths.runtimes.appendingPathComponent(runtime.id)
        do {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}
