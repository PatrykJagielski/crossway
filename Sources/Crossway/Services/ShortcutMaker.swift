import Foundation
import AppKit

/// Creates small `.app` bundles in ~/Applications/Crossway that start a Windows program
/// in its bottle — so games show up in Launchpad, Spotlight and the Dock.
enum ShortcutMaker {
    static func createShortcut(name: String, program: PinnedProgram, bottle: Bottle) throws -> URL {
        let fm = FileManager.default
        let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "-")
        let app = Paths.shortcuts.appendingPathComponent("\(safeName).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": "\(Paths.bundleIdentifier).shortcut.\(program.id.uuidString.lowercased())",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleIconFile": "AppIcon",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            try? fm.copyItem(at: icon, to: resources.appendingPathComponent("AppIcon.icns"))
        }

        let binary = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        let script = """
        #!/bin/sh
        # Wygenerowane przez Crossway — uruchamia „\(name.replacingOccurrences(of: "\"", with: ""))” w butelce „\(bottle.name.replacingOccurrences(of: "\"", with: ""))”.
        CROSSWAY=\(shellQuote(binary))
        if [ ! -x "$CROSSWAY" ]; then
            APP="$(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "\(Paths.bundleIdentifier)"' | /usr/bin/head -n 1)"
            CROSSWAY="$APP/Contents/MacOS/Crossway"
        fi
        exec "$CROSSWAY" --launch \(shellQuote(bottle.id.uuidString)) \(shellQuote(program.path)) \(shellQuote(program.arguments))

        """
        let launcher = macOS.appendingPathComponent("launcher")
        try script.write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        return app
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// `Crossway --launch <bottle-uuid> <unix-path> [arguments]` — used by the .app shortcuts.
enum CommandLineLauncher {
    static func handle(_ arguments: [String]) -> Int32? {
        guard arguments.count >= 2, arguments[1] == "--launch" else { return nil }
        guard arguments.count >= 4, let bottleID = UUID(uuidString: arguments[2]) else {
            FileHandle.standardError.write(Data("Użycie: Crossway --launch <id-butelki> <ścieżka> [argumenty]\n".utf8))
            return 64
        }
        let path = arguments[3]
        let extra = arguments.count > 4 ? arguments[4] : ""

        guard let bottle = BottleIO.loadAll().first(where: { $0.id == bottleID }) else {
            alert("Nie znaleziono butelki dla tego skrótu. Mogła zostać usunięta.")
            return 1
        }
        guard let runtime = RuntimeDiscovery.runtime(id: bottle.runtimeID) else {
            alert("Brak środowiska Wine „\(bottle.runtimeID)” dla butelki „\(bottle.name)”.")
            return 1
        }
        let (url, extraArguments) = SteamFix.prepare(file: URL(fileURLWithPath: path), arguments: extra, in: bottle)
        do {
            let process = try WineLauncher.makeProcess(
                bottle: bottle,
                runtime: runtime,
                arguments: WineLauncher.wineArguments(forFile: url, extraArguments: WineLauncher.splitArguments(extraArguments)),
                workingDirectory: url.deletingLastPathComponent(),
                logURL: WineLauncher.newLogURL(bottle: bottle, label: url.deletingPathExtension().lastPathComponent)
            )
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            alert("Nie udało się uruchomić programu: \(error.localizedDescription)")
            return 1
        }
    }

    private static func alert(_ message: String) {
        let script = "display alert \"Crossway\" message \"\(message.replacingOccurrences(of: "\"", with: "'"))\" as critical"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
}
