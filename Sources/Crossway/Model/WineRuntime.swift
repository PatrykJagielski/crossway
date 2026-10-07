import Foundation

/// A Wine build that bottles can run on (e.g. Game Porting Toolkit with D3DMetal).
struct WineRuntime: Identifiable, Hashable, Codable {
    enum Source: String, Codable {
        case managed   // downloaded by Crossway into Paths.runtimes
        case whisky    // reused from an existing Whisky installation
        case external  // a Wine .app found in /Applications
    }

    var id: String
    var name: String
    var version: String
    /// Directory that contains `bin/`, `lib/` and `share/`.
    var wineRoot: URL
    var source: Source

    var binDirectory: URL { wineRoot.appendingPathComponent("bin") }

    /// `wine64` on Wine ≤ 8 / GPTK builds, `wine` on new WoW64 builds (Wine 9+).
    var wineBinary: URL {
        let wine64 = binDirectory.appendingPathComponent("wine64")
        if FileManager.default.isExecutableFile(atPath: wine64.path) { return wine64 }
        return binDirectory.appendingPathComponent("wine")
    }

    var wineserver: URL { binDirectory.appendingPathComponent("wineserver") }

    var d3dMetalFramework: URL {
        wineRoot.appendingPathComponent("lib/external/D3DMetal.framework")
    }

    var hasD3DMetal: Bool { FileManager.default.directoryExists(d3dMetalFramework) }

    var d3dMetalVersion: String? {
        let plist = d3dMetalFramework.appendingPathComponent("Versions/A/Resources/version.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Supports DLSS → MetalFX translation (GPTK 2.1+).
    var hasMetalFXShim: Bool {
        FileManager.default.fileExists(atPath: wineRoot.appendingPathComponent("lib/wine/x86_64-windows/nvngx-on-metalfx.dll").path)
    }

    /// Vulkan (MoltenVK) is required for DXVK. GPTK builds ship without it.
    var hasVulkan: Bool {
        FileManager.default.fileExists(atPath: wineRoot.appendingPathComponent("lib/libMoltenVK.dylib").path)
    }

    var isUsable: Bool {
        FileManager.default.isExecutableFile(atPath: wineBinary.path)
            && FileManager.default.isExecutableFile(atPath: wineserver.path)
    }

    var graphicsSummary: String {
        if hasD3DMetal {
            return "D3DMetal \(d3dMetalVersion ?? "")".trimmingCharacters(in: .whitespaces)
        }
        return "WineD3D"
    }
}

/// Manifest written next to a runtime that Crossway downloaded itself.
struct RuntimeManifest: Codable {
    var id: String
    var name: String
    var version: String
    /// Path of the wine root relative to the runtime folder.
    var wineRootRelative: String
    var installed: Date
}

/// Finds every runtime on this Mac. Pure file-system work, safe to call from any thread.
enum RuntimeDiscovery {
    static let manifestName = "runtime.json"

    static func all() -> [WineRuntime] {
        var result: [WineRuntime] = []
        let fm = FileManager.default

        // 1. Runtimes downloaded by Crossway.
        if let dirs = try? fm.contentsOfDirectory(at: Paths.runtimes, includingPropertiesForKeys: nil) {
            for dir in dirs where fm.directoryExists(dir) {
                let manifestURL = dir.appendingPathComponent(manifestName)
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder.crossway.decode(RuntimeManifest.self, from: data) else { continue }
                let runtime = WineRuntime(
                    id: manifest.id,
                    name: manifest.name,
                    version: manifest.version,
                    wineRoot: dir.appendingPathComponent(manifest.wineRootRelative),
                    source: .managed
                )
                if runtime.isUsable { result.append(runtime) }
            }
        }

        // 2. Whisky's bundled WhiskyWine (Wine 7.7 + D3DMetal).
        let whiskyWine = Paths.whiskyLibraries.appendingPathComponent("Wine")
        let whisky = WineRuntime(
            id: "whisky",
            name: "WhiskyWine (z aplikacji Whisky)",
            version: whiskyVersion() ?? "",
            wineRoot: whiskyWine,
            source: .whisky
        )
        if whisky.isUsable { result.append(whisky) }

        // 3. Wine apps installed system-wide (Homebrew casks from Gcenx / WineHQ).
        let apps = ["Game Porting Toolkit", "Wine Devel", "Wine Staging", "Wine Stable", "Wine Crossover"]
        for app in apps {
            for base in ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
                let bundle = URL(fileURLWithPath: base).appendingPathComponent("\(app).app")
                let root = bundle.appendingPathComponent("Contents/Resources/wine")
                let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
                let runtime = WineRuntime(
                    id: "app:\(bundle.path)",
                    name: app,
                    version: info?["CFBundleShortVersionString"] as? String ?? "",
                    wineRoot: root,
                    source: .external
                )
                if runtime.isUsable { result.append(runtime) }
            }
        }
        return result
    }

    static func runtime(id: String) -> WineRuntime? {
        all().first { $0.id == id }
    }

    private static func whiskyVersion() -> String? {
        let url = Paths.whiskyLibraries.appendingPathComponent("WhiskyWineVersion.plist")
        guard let dict = NSDictionary(contentsOf: url),
              let version = dict["version"] as? [String: Any],
              let major = version["major"] as? Int,
              let minor = version["minor"] as? Int,
              let patch = version["patch"] as? Int else { return nil }
        return "\(major).\(minor).\(patch)"
    }
}

extension JSONDecoder {
    static let crossway: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let crossway: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
