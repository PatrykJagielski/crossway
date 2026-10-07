import Foundation

/// Locations of everything Crossway stores on disk.
enum Paths {
    static let bundleIdentifier = "pl.crossway.app"

    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Crossway", isDirectory: true)
    }()

    static var runtimes: URL { appSupport.appendingPathComponent("Runtimes", isDirectory: true) }
    static var bottles: URL { appSupport.appendingPathComponent("Bottles", isDirectory: true) }
    static var logs: URL { appSupport.appendingPathComponent("Logs", isDirectory: true) }
    static var downloads: URL { appSupport.appendingPathComponent("Downloads", isDirectory: true) }
    static var components: URL { appSupport.appendingPathComponent("Components", isDirectory: true) }
    static var dxvk: URL { components.appendingPathComponent("DXVK", isDirectory: true) }
    static var winetricks: URL { components.appendingPathComponent("winetricks") }

    /// `.app` launchers created for individual programs (visible in Launchpad / Spotlight).
    static var shortcuts: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Crossway", isDirectory: true)
    }

    /// Runtime shipped with the (archived) Whisky app, reused when present.
    static var whiskyLibraries: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.isaacmarovitz.Whisky/Libraries", isDirectory: true)
    }

    static func ensureDirectories() {
        for url in [appSupport, runtimes, bottles, logs, downloads, components] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static var rosettaInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    static var cabextractPath: String? {
        ["/opt/homebrew/bin/cabextract", "/usr/local/bin/cabextract"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var homebrewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

extension FileManager {
    func directoryExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
