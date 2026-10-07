import Foundation
import AppKit

@MainActor
final class BottleManager: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    /// Bottle ID → what is currently happening to it (creating, applying settings…).
    @Published private(set) var busy: [UUID: String] = [:]
    @Published var lastError: String?

    let runner: WineRunner
    let runtimes: RuntimeManager

    init(runner: WineRunner, runtimes: RuntimeManager) {
        self.runner = runner
        self.runtimes = runtimes
        reload()
    }

    func reload() {
        bottles = BottleIO.loadAll()
    }

    func bottle(id: UUID?) -> Bottle? {
        guard let id else { return nil }
        return bottles.first { $0.id == id }
    }

    func runtime(for bottle: Bottle) throws -> WineRuntime {
        guard let runtime = runtimes.runtime(id: bottle.runtimeID) else {
            throw CrosswayError.runtimeMissing(bottle.runtimeID)
        }
        return runtime
    }

    func save(_ bottle: Bottle) {
        do {
            try BottleIO.save(bottle)
            if let index = bottles.firstIndex(where: { $0.id == bottle.id }) {
                bottles[index] = bottle
            } else {
                bottles.append(bottle)
            }
            bottles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            lastError = "Nie udało się zapisać butelki: \(error.localizedDescription)"
        }
    }

    // MARK: - Creating

    func create(name: String, runtime: WineRuntime, settings: BottleSettings) async -> Bottle? {
        let id = UUID()
        let bottle = Bottle(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Nowa butelka" : name,
            runtimeID: runtime.id,
            settings: settings,
            url: Paths.bottles.appendingPathComponent(id.uuidString, isDirectory: true)
        )
        save(bottle)
        busy[id] = "Tworzenie prefiksu Wine… (pierwsze uruchomienie może potrwać minutę)"
        defer { busy[id] = nil }
        do {
            let code = try await runner.runAndWait(["wineboot", "--init"], name: "wineboot", in: bottle, runtime: runtime)
            await runner.waitForWineserver(in: bottle, runtime: runtime)
            guard code == 0, bottle.isInitialized else { throw CrosswayError.processFailed("wineboot", code) }
            try await applySystemSettings(bottle, runtime: runtime, previous: nil)
            return bottle
        } catch {
            lastError = "Tworzenie butelki „\(bottle.name)”: \(error.localizedDescription)"
            return bottle
        }
    }

    // MARK: - Settings

    /// Saves new settings and pushes whatever lives inside the prefix (registry, DLLs).
    func update(_ bottle: Bottle, previous: Bottle) async {
        save(bottle)
        let s = bottle.settings, p = previous.settings
        let needsPrefixWork = s.windowsVersion != p.windowsVersion || s.retinaMode != p.retinaMode
            || s.commandAsControl != p.commandAsControl || s.graphics != p.graphics
            || s.metalFX != p.metalFX || bottle.runtimeID != previous.runtimeID
        guard needsPrefixWork else { return }
        busy[bottle.id] = "Zapisywanie ustawień w butelce…"
        defer { busy[bottle.id] = nil }
        do {
            let runtime = try runtime(for: bottle)
            if bottle.runtimeID != previous.runtimeID {
                // Different Wine version: let wineboot upgrade the prefix.
                _ = try await runner.runAndWait(["wineboot", "--update"], name: "wineboot-update", in: bottle, runtime: runtime)
            }
            try await applySystemSettings(bottle, runtime: runtime, previous: previous)
        } catch {
            lastError = "Ustawienia „\(bottle.name)”: \(error.localizedDescription)"
        }
    }

    private func applySystemSettings(_ bottle: Bottle, runtime: WineRuntime, previous: Bottle?) async throws {
        let s = bottle.settings
        try installGraphicsDLLs(bottle, runtime: runtime)

        if previous == nil || previous?.settings.windowsVersion != s.windowsVersion || previous?.runtimeID != bottle.runtimeID {
            busy[bottle.id] = "Ustawianie wersji Windows (\(s.windowsVersion.title))…"
            _ = try await runner.runAndWait(["winecfg", "-v", s.windowsVersion.rawValue], name: "winecfg-version", in: bottle, runtime: runtime)
        }

        busy[bottle.id] = "Zapisywanie rejestru…"
        let yesNo: (Bool) -> String = { $0 ? "y" : "n" }
        let dpi = s.retinaMode ? 192 : 96
        let reg = """
        REGEDIT4

        [HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]
        "RetinaMode"="\(yesNo(s.retinaMode))"
        "LeftCommandIsCtrl"="\(yesNo(s.commandAsControl))"
        "RightCommandIsCtrl"="\(yesNo(s.commandAsControl))"

        [HKEY_CURRENT_USER\\Control Panel\\Desktop]
        "LogPixels"=dword:\(String(format: "%08x", dpi))

        [HKEY_CURRENT_CONFIG\\Software\\Fonts]
        "LogPixels"=dword:\(String(format: "%08x", dpi))

        """
        let regFile = bottle.driveC.appendingPathComponent("crossway-settings.reg")
        try reg.data(using: .utf8)!.write(to: regFile)
        let windowsPath = bottle.windowsPath(for: regFile) ?? "C:\\crossway-settings.reg"
        let code = try await runner.runAndWait(["regedit", "/S", windowsPath], name: "regedit-settings", in: bottle, runtime: runtime)
        try? FileManager.default.removeItem(at: regFile)
        // No `wineserver -w` here: it would block until every program in the bottle
        // (e.g. a running Steam) exits. regedit has already handed the keys to wineserver.
        if code != 0 { throw CrosswayError.processFailed("regedit", code) }
    }

    /// Copies DXVK / DLSS→MetalFX DLLs into the prefix when those options are on.
    private func installGraphicsDLLs(_ bottle: Bottle, runtime: WineRuntime) throws {
        let fm = FileManager.default
        let system32 = bottle.driveC.appendingPathComponent("windows/system32")
        let syswow64 = bottle.driveC.appendingPathComponent("windows/syswow64")

        if WineLauncher.effectiveBackend(bottle.settings, runtime: runtime) == .dxvk, runtime.bundledDXVK == nil {
            guard runtime.hasVulkan else {
                throw CrosswayError.message("Środowisko „\(runtime.name)” nie obsługuje Vulkana, więc DXVK nie zadziała. Wybierz D3DMetal albo środowisko Wine Staging.")
            }
            guard runtimes.dxvkInstalled else {
                throw CrosswayError.message("DXVK nie jest pobrany. Otwórz Środowiska i pobierz „DXVK-macOS”, potem zapisz ustawienia ponownie.")
            }
            try copyDLLs(from: Paths.dxvk.appendingPathComponent("x64"), to: system32)
            if fm.directoryExists(syswow64) {
                try copyDLLs(from: Paths.dxvk.appendingPathComponent("x32"), to: syswow64)
            }
        }

        if bottle.settings.metalFX && runtime.hasMetalFXShim {
            let dlls = runtime.wineRoot.appendingPathComponent("lib/wine/x86_64-windows")
            try replace(system32.appendingPathComponent("nvngx.dll"), with: dlls.appendingPathComponent("nvngx-on-metalfx.dll"))
            try replace(system32.appendingPathComponent("nvapi64.dll"), with: dlls.appendingPathComponent("nvapi64.dll"))
        }
    }

    private func copyDLLs(from source: URL, to target: URL) throws {
        let fm = FileManager.default
        guard fm.directoryExists(source) else { return }
        for dll in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) where dll.pathExtension == "dll" {
            try replace(target.appendingPathComponent(dll.lastPathComponent), with: dll)
        }
    }

    private func replace(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: source, to: target)
    }

    // MARK: - Programs

    func pin(_ program: PinnedProgram, in bottle: Bottle) {
        var copy = bottle
        guard !copy.programs.contains(where: { $0.path == program.path }) else { return }
        copy.programs.append(program)
        save(copy)
    }

    func unpin(path: String, in bottle: Bottle) {
        var copy = bottle
        copy.programs.removeAll { $0.path == path }
        save(copy)
    }

    func updateProgram(_ program: PinnedProgram, in bottle: Bottle) {
        var copy = bottle
        if let index = copy.programs.firstIndex(where: { $0.id == program.id }) {
            copy.programs[index] = program
        } else {
            copy.programs.append(program)
        }
        save(copy)
    }

    // MARK: - Delete / duplicate

    func delete(_ bottle: Bottle) {
        if let runtime = try? runtime(for: bottle) {
            runner.killAll(in: bottle, runtime: runtime)
        }
        do {
            try FileManager.default.trashItem(at: bottle.url, resultingItemURL: nil)
            bottles.removeAll { $0.id == bottle.id }
        } catch {
            lastError = "Nie udało się przenieść butelki do Kosza: \(error.localizedDescription)"
        }
    }

    func duplicate(_ bottle: Bottle) async {
        var copy = bottle
        copy.id = UUID()
        copy.name = bottle.name + " (kopia)"
        copy.created = Date()
        copy.url = Paths.bottles.appendingPathComponent(copy.id.uuidString, isDirectory: true)
        busy[bottle.id] = "Kopiowanie butelki…"
        defer { busy[bottle.id] = nil }
        let source = bottle.url, target = copy.url
        do {
            // `cp -c` uses APFS clones: instant and takes no extra space.
            let (code, output) = try await Shell.run("/bin/cp", ["-cR", source.path, target.path])
            guard code == 0 else { throw CrosswayError.message(output) }
            // Programs pinned inside the old prefix must point into the copy.
            copy.programs = copy.programs.map { program in
                var p = program
                if p.path.hasPrefix(source.path) {
                    p.path = target.path + p.path.dropFirst(source.path.count)
                }
                return p
            }
            save(copy)
        } catch {
            lastError = "Kopiowanie butelki: \(error.localizedDescription)"
        }
    }
}
