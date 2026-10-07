import Foundation

/// Builds Wine processes for a bottle: environment, command line and log file.
/// Thread-agnostic so it can be used both by the UI and by `.app` shortcuts (CLI mode).
enum WineLauncher {
    static let dxvkOverrides = "dxgi,d3d9,d3d10core,d3d11=n,b"

    static func environment(bottle: Bottle, runtime: WineRuntime) -> [String: String] {
        let s = bottle.settings
        var env = ProcessInfo.processInfo.environment
        // Never leak a prefix from the user's shell into a bottle.
        for key in ["WINEPREFIX", "WINEARCH", "WINEDLLOVERRIDES", "WINESERVER", "WINELOADER", "WINEDEBUG"] {
            env.removeValue(forKey: key)
        }

        env["WINEPREFIX"] = bottle.url.path
        env["WINESERVER"] = runtime.wineserver.path
        env["PATH"] = [runtime.binDirectory.path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
        env["WINEDEBUG"] = s.verboseLogging ? "+loaddll,+seh,warn+all,fixme-all" : "fixme-all"
        env["LANG"] = env["LANG"] ?? "pl_PL.UTF-8"

        switch s.sync {
        case .none: break
        case .esync: env["WINEESYNC"] = "1"
        case .msync: env["WINEMSYNC"] = "1"; env["WINEESYNC"] = "1"
        }

        if s.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if s.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        if s.raytracing { env["D3DM_SUPPORT_DXR"] = "1" }
        if s.metalFX { env["D3DM_ENABLE_METALFX"] = "1" }

        // winemenubuilder litters ~/Applications and the Dock with half-working entries.
        var overrides = ["winemenubuilder.exe=d"]
        if s.graphics == .dxvk && runtime.hasVulkan {
            overrides.append(dxvkOverrides)
            if s.dxvkAsync { env["DXVK_ASYNC"] = "1" }
            env["DXVK_HUD"] = s.dxvkHUD ? "fps,devinfo,gpuload" : nil
            env["DXVK_LOG_LEVEL"] = s.verboseLogging ? "info" : "warn"
        }
        if s.metalFX && runtime.hasMetalFXShim {
            overrides.append("nvapi,nvapi64,nvngx=n,b")
        }
        let custom = s.dllOverrides.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { overrides.append(custom) }
        env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")

        for variable in s.environment where !variable.key.isEmpty {
            env[variable.key] = variable.value
        }
        return env
    }

    /// Wine arguments needed to open a given file (exe, msi, bat, lnk).
    static func wineArguments(forFile url: URL, extraArguments: [String]) -> [String] {
        switch url.pathExtension.lowercased() {
        case "msi":
            return ["msiexec", "/i", url.path] + extraArguments
        case "bat", "cmd":
            return ["cmd", "/c", url.path] + extraArguments
        case "lnk":
            return ["start", "/wait", "/unix", url.path] + extraArguments
        default:
            return [url.path] + extraArguments
        }
    }

    /// Creates (but does not start) a Wine process. Output goes to `logURL`.
    static func makeProcess(
        bottle: Bottle,
        runtime: WineRuntime,
        arguments: [String],
        workingDirectory: URL? = nil,
        logURL: URL
    ) throws -> Process {
        let process = Process()
        process.executableURL = runtime.wineBinary
        process.arguments = arguments
        process.environment = environment(bottle: bottle, runtime: runtime)
        // drive_c does not exist until wineboot has run for the first time.
        let fallback = FileManager.default.directoryExists(bottle.driveC) ? bottle.driveC : bottle.url
        process.currentDirectoryURL = workingDirectory.flatMap { FileManager.default.directoryExists($0) ? $0 : nil } ?? fallback

        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: header(bottle: bottle, runtime: runtime, arguments: arguments, env: process.environment ?? [:]))
        let handle = try FileHandle(forWritingTo: logURL)
        handle.seekToEndOfFile()
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        return process
    }

    static func newLogURL(bottle: Bottle, label: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let safe = label.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "_")
        return bottle.logsDirectory.appendingPathComponent("\(formatter.string(from: Date()))_\(safe).log")
    }

    private static func header(bottle: Bottle, runtime: WineRuntime, arguments: [String], env: [String: String]) -> Data {
        let interesting = env.filter { key, _ in
            key.hasPrefix("WINE") || key.hasPrefix("DXVK") || key.hasPrefix("D3DM") || key.hasPrefix("MTL") || key.hasPrefix("ROSETTA")
        }
        var text = "Crossway — \(Date())\n"
        text += "Butelka: \(bottle.name) (\(bottle.url.path))\n"
        text += "Środowisko: \(runtime.name) \(runtime.version) — \(runtime.wineRoot.path)\n"
        text += "Polecenie: \(runtime.wineBinary.lastPathComponent) \(arguments.joined(separator: " "))\n"
        for (key, value) in interesting.sorted(by: { $0.key < $1.key }) {
            text += "  \(key)=\(value)\n"
        }
        text += String(repeating: "-", count: 72) + "\n"
        return Data(text.utf8)
    }

    /// Splits a command-line string into arguments, honouring "double" and 'single' quotes.
    static func splitArguments(_ string: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        for ch in string {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                hasToken = true
            } else if ch.isWhitespace {
                if hasToken || !current.isEmpty { result.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(ch)
            }
        }
        if hasToken || !current.isEmpty { result.append(current) }
        return result
    }
}
