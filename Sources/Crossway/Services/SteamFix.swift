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
                    $0.command.localizedCaseInsensitiveContains("\\steamwebhelper.exe")
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
