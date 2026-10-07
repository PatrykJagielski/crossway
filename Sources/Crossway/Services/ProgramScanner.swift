import Foundation

struct DiscoveredProgram: Identifiable, Hashable {
    enum Kind { case shortcut, executable }
    var id: String { url.path }
    let name: String
    let url: URL
    let kind: Kind
    /// Start-menu folder or the folder the exe lives in, for display.
    let location: String
}

/// Finds programs installed inside a bottle: Start Menu / Desktop shortcuts and .exe files.
enum ProgramScanner {
    private static let junk = [
        "unins", "uninstall", "odinstaluj", "crashreport", "crashhandler", "crashpad", "crash_reporter",
        "setup", "install", "redist", "vcredist", "vc_redist", "dxsetup", "dotnet", "update", "updater",
        "helper", "errorreporter", "bugreport", "report", "cefprocess", "webhelper", "service",
        "elevate", "launcherpatcher", "touchup", "cleanup", "repair", "notification", "overlay",
        "unitycrashhandler", "ue4prereq", "prereq", "easyanticheat_setup", "be_service", "steamerrorreporter",
        "website", "readme", "manual", "help", "license", "support",
    ]

    static func isJunk(_ name: String) -> Bool {
        let lower = name.lowercased()
        return junk.contains { lower.contains($0) }
    }

    static func shortcuts(in bottle: Bottle) -> [DiscoveredProgram] {
        let fm = FileManager.default
        var roots = [bottle.driveC.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu")]
        let users = bottle.driveC.appendingPathComponent("users")
        for user in (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            roots.append(user.appendingPathComponent("AppData/Roaming/Microsoft/Windows/Start Menu"))
            roots.append(user.appendingPathComponent("Desktop"))
            roots.append(user.appendingPathComponent("Pulpit"))
        }

        var seen = Set<String>()
        var result: [DiscoveredProgram] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "lnk" {
                let name = url.deletingPathExtension().lastPathComponent
                guard !isJunk(name), seen.insert(name.lowercased()).inserted else { continue }
                result.append(DiscoveredProgram(name: name, url: url, kind: .shortcut, location: url.deletingLastPathComponent().lastPathComponent))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every .exe under Program Files / Program Files (x86) / Games, minus installers and helpers.
    static func executables(in bottle: Bottle, limit: Int = 400) -> [DiscoveredProgram] {
        let fm = FileManager.default
        let roots = ["Program Files", "Program Files (x86)", "Games", "GOG Games"]
            .map { bottle.driveC.appendingPathComponent($0) }
        let skippedDirs: Set<String> = [
            "Common Files", "Windows NT", "Internet Explorer", "Windows Media Player", "Windows Mail",
            "Microsoft.NET", "Mono", "Microsoft", "Wine", "_CommonRedist", "CommonRedist", "Redist",
            "DirectX", "Installer", "Support", "EasyAntiCheat", "BattlEye", "Engine",
        ]
        var result: [DiscoveredProgram] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > 6 { enumerator.skipDescendants(); continue }
                if skippedDirs.contains(url.lastPathComponent),
                   (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "exe" else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                guard !isJunk(name) else { continue }
                let folder = url.deletingLastPathComponent().path.replacingOccurrences(of: bottle.driveC.path + "/", with: "C:/")
                result.append(DiscoveredProgram(name: name, url: url, kind: .executable, location: folder))
                if result.count >= limit { return result }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
