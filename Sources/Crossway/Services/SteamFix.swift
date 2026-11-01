import Foundation

/// Makes Valve's Steam client usable under Wine on Apple Silicon.
///
/// Steam's CEF (Chromium) UI paints a black window: ANGLE cannot query the DXGI
/// adapter, drops to GLES 2.0, disables the GPU and renders its transparent window
/// black. We replace `steamwebhelper.exe` with a tiny wrapper that relaunches the real
/// helper with `--disable-gpu --single-process`, and start Steam with `-noverifyfiles`
/// so its boot-time checksum pass does not put the original binary back.
enum SteamFix {
    static let realBinaryName = "steamwebhelper_real.exe"
    /// Valve's helper is several MB; the wrapper is ~20 KB.
    private static let wrapperSizeCeiling = 500_000

    static var wrapperURL: URL? {
        if let url = Bundle.main.url(forResource: "steamwebhelper-wrapper", withExtension: "exe") { return url }
        // `swift run` during development: next to the sources.
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/steamwebhelper-wrapper.exe")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func steamDirectory(in bottle: Bottle) -> URL? {
        for folder in ["Program Files (x86)/Steam", "Program Files/Steam"] {
            let dir = bottle.driveC.appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("steam.exe").path) { return dir }
        }
        return nil
    }

    static func isSteamLauncher(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == "steam.exe" || name == "steam.lnk"
    }

    /// Call before launching any file. Returns the file and arguments to actually use.
    static func prepare(file url: URL, arguments: String, in bottle: Bottle) -> (URL, String) {
        guard isSteamLauncher(url), let steam = steamDirectory(in: bottle) else { return (url, arguments) }
        installWrapper(steamDirectory: steam)
        guardWrapper(steamDirectory: steam, in: bottle)
        var args = arguments
        if !args.contains("-noverifyfiles") {
            args = (args + " -noverifyfiles").trimmingCharacters(in: .whitespaces)
        }
        // A .lnk cannot carry our extra argument — start steam.exe directly instead.
        return (steam.appendingPathComponent("steam.exe"), args)
    }

    /// Steam applies client updates right after it starts, which puts Valve's helper back
    /// over the wrapper (the UI then hangs or goes black). Watch the CEF folders for a few
    /// minutes; when that happens, re-install the wrapper (keeping the new helper as
    /// `_real`) and kill the unwrapped helper so Steam relaunches it through the wrapper.
    static func guardWrapper(steamDirectory steam: URL, in bottle: Bottle, duration: TimeInterval = 240) {
        DispatchQueue.global(qos: .utility).async {
            let deadline = Date().addingTimeInterval(duration)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 1)
                guard valveHelperIsActive(steamDirectory: steam) else { continue }
                // Let the updater finish writing before we touch the files.
                Thread.sleep(forTimeInterval: 3)
                installWrapper(steamDirectory: steam)
                let unwrapped = WineProcessKiller.processes(in: bottle).filter {
                    WineProcessKiller.command($0.command, runs: "steamwebhelper.exe")
                }
                WineProcessKiller.kill(unwrapped)
            }
        }
    }

    private static func valveHelperIsActive(steamDirectory steam: URL) -> Bool {
        let cefRoot = steam.appendingPathComponent("bin/cef")
        let dirs = (try? FileManager.default.contentsOfDirectory(at: cefRoot, includingPropertiesForKeys: nil)) ?? []
        return dirs.contains { dir in
            dir.lastPathComponent.hasPrefix("cef.win")
                && (size(of: dir.appendingPathComponent("steamwebhelper.exe")) ?? 0) >= wrapperSizeCeiling
        }
    }

    /// An executable installed by Steam (…/steamapps/common/…).
    static func isSteamGame(_ url: URL) -> Bool {
        url.path.lowercased().contains("/steamapps/common/") && url.pathExtension.lowercased() == "exe"
    }

    /// Steam app id of a game exe under `steamapps/common/<installdir>/…`, read from the
    /// matching `steamapps/appmanifest_<id>.acf`.
    static func appID(forGame exe: URL) -> String? {
        let parts = exe.standardizedFileURL.pathComponents
        guard let common = parts.lastIndex(where: { $0.lowercased() == "common" }), common > 0,
              parts[common - 1].lowercased() == "steamapps", common + 1 < parts.count else { return nil }
        let installDir = parts[common + 1].lowercased()
        let steamapps = URL(fileURLWithPath: NSString.path(withComponents: Array(parts[...(common - 1)])))
        let manifests = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
            guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
            if acfValue("installdir", in: text)?.lowercased() == installDir { return acfValue("appid", in: text) }
        }
        return nil
    }

    private static func acfValue(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\"", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if fields.count >= 2, fields[0].lowercased() == key { return fields[1] }
        }
        return nil
    }

    /// A Steam game started from its exe normally restarts itself through Steam and then
    /// inherits Steam's environment — losing a per-program renderer. `steam_appid.txt` next
    /// to the exe makes the Steam API skip that restart, so the game stays in our process.
    /// Steam itself must still be running and logged on.
    @discardableResult
    static func keepGameInOwnProcess(_ exe: URL) -> Bool {
        guard let id = appID(forGame: exe) else { return false }
        let file = exe.deletingLastPathComponent().appendingPathComponent("steam_appid.txt")
        if let existing = try? String(contentsOf: file, encoding: .utf8),
           existing.trimmingCharacters(in: .whitespacesAndNewlines) == id { return true }
        return (try? id.write(to: file, atomically: true, encoding: .utf8)) != nil
    }

    static func steamIsRunning(in bottle: Bottle) -> Bool {
        WineProcessKiller.processes(in: bottle).contains { WineProcessKiller.command($0.command, runs: "steam.exe") }
    }

    /// Starts Steam in the bottle (if needed) and waits until it has logged on.
    static func ensureSteamRunning(in bottle: Bottle, runtime: WineRuntime, timeout: TimeInterval = 90) {
        guard !steamIsRunning(in: bottle), let steam = steamDirectory(in: bottle) else { return }
        let log = steam.appendingPathComponent("logs/connection_log.txt")
        let startOffset = (try? FileManager.default.attributesOfItem(atPath: log.path)[.size] as? NSNumber)?.intValue ?? 0

        let (url, arguments) = prepare(file: steam.appendingPathComponent("steam.exe"), arguments: "", in: bottle)
        guard let process = try? WineLauncher.makeProcess(
            bottle: bottle, runtime: runtime,
            arguments: WineLauncher.wineArguments(forFile: url, extraArguments: WineLauncher.splitArguments(arguments)),
            workingDirectory: steam,
            logURL: WineLauncher.newLogURL(bottle: bottle, label: "steam")
        ), (try? process.run()) != nil else { return }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 2)
            guard let handle = try? FileHandle(forReadingFrom: log) else { continue }
            try? handle.seek(toOffset: UInt64(startOffset))
            let fresh = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
            try? handle.close()
            if fresh.contains("[Logged On") {
                Thread.sleep(forTimeInterval: 3) // let the client settle before launching a game
                return
            }
        }
    }

    /// Blocks while a process with this executable name runs in the bottle.
    static func waitForGame(named exe: String, in bottle: Bottle, appearTimeout: TimeInterval = 120) {
        func running() -> Bool {
            WineProcessKiller.processes(in: bottle).contains { WineProcessKiller.command($0.command, runs: exe) }
        }
        let appearDeadline = Date().addingTimeInterval(appearTimeout)
        while !running() {
            if Date() > appearDeadline { return }
            Thread.sleep(forTimeInterval: 2)
        }
        while running() { Thread.sleep(forTimeInterval: 3) }
    }

    static func installWrapper(steamDirectory steam: URL) {
        let fm = FileManager.default
        guard let wrapper = wrapperURL else { return }
        let cefRoot = steam.appendingPathComponent("bin/cef")
        let dirs = (try? fm.contentsOfDirectory(at: cefRoot, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs where dir.lastPathComponent.hasPrefix("cef.win") {
            let target = dir.appendingPathComponent("steamwebhelper.exe")
            let real = dir.appendingPathComponent(realBinaryName)
            guard let targetSize = size(of: target) else { continue }
            if targetSize >= wrapperSizeCeiling {
                // Valve's binary (fresh install or Steam updated it): stash it as the real one.
                try? fm.removeItem(at: real)
                guard (try? fm.copyItem(at: target, to: real)) != nil else { continue }
            } else if (size(of: real) ?? 0) < wrapperSizeCeiling {
                continue // both small: the real helper is gone, leave things alone
            }
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: wrapper, to: target)
        }
    }

    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
