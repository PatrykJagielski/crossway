import Foundation

enum WindowsVersion: String, Codable, CaseIterable, Identifiable {
    case win11, win10, win81, win7, winxp
    var id: String { rawValue }

    var title: String {
        switch self {
        case .win11: return "Windows 11"
        case .win10: return "Windows 10"
        case .win81: return "Windows 8.1"
        case .win7: return "Windows 7"
        case .winxp: return "Windows XP"
        }
    }
}

enum GraphicsBackend: String, Codable, CaseIterable, Identifiable {
    /// The runtime's best option (D3DMetal when available).
    case automatic
    /// Apple's D3DMetal (DirectX 11/12 → Metal), from GPTK or a Sikarugir renderer.
    case d3dmetal
    /// DXMT (DirectX 10/11 → Metal), open source.
    case dxmt
    /// DXVK (DirectX 9–11 → Vulkan → MoltenVK → Metal).
    case dxvk
    /// Wine's own WineD3D (OpenGL).
    case wined3d
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatycznie"
        case .d3dmetal: return "D3DMetal (DirectX 11/12 → Metal)"
        case .dxmt: return "DXMT (DirectX 10/11 → Metal)"
        case .dxvk: return "DXVK (DirectX 9–11 → Vulkan → Metal)"
        case .wined3d: return "WineD3D (OpenGL)"
        }
    }

    var shortTitle: String {
        switch self {
        case .automatic: return "Auto"
        case .d3dmetal: return "D3DMetal"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .wined3d: return "WineD3D"
        }
    }
}

enum SyncMode: String, Codable, CaseIterable, Identifiable {
    case none, esync, msync
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Wyłączona"
        case .esync: return "ESync"
        case .msync: return "MSync (tylko CrossOver-owe buildy)"
        }
    }
}

struct EnvironmentVariable: Codable, Hashable, Identifiable {
    var id = UUID()
    var key: String
    var value: String
}

struct BottleSettings: Codable, Hashable {
    var windowsVersion: WindowsVersion = .win10
    var graphics: GraphicsBackend = .automatic
    var sync: SyncMode = .esync
    var metalHUD = false
    var advertiseAVX = true
    var raytracing = false
    var metalFX = false
    var dxvkAsync = true
    var dxvkHUD = false
    var retinaMode = false
    var commandAsControl = false
    var verboseLogging = false
    var dllOverrides = ""
    var environment: [EnvironmentVariable] = []

    init() {}

    // Tolerant decoding so that older bottle files keep working when new settings appear.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BottleSettings()
        windowsVersion = try c.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion) ?? d.windowsVersion
        graphics = try c.decodeIfPresent(GraphicsBackend.self, forKey: .graphics) ?? d.graphics
        sync = try c.decodeIfPresent(SyncMode.self, forKey: .sync) ?? d.sync
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? d.metalHUD
        advertiseAVX = try c.decodeIfPresent(Bool.self, forKey: .advertiseAVX) ?? d.advertiseAVX
        raytracing = try c.decodeIfPresent(Bool.self, forKey: .raytracing) ?? d.raytracing
        metalFX = try c.decodeIfPresent(Bool.self, forKey: .metalFX) ?? d.metalFX
        dxvkAsync = try c.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? d.dxvkAsync
        dxvkHUD = try c.decodeIfPresent(Bool.self, forKey: .dxvkHUD) ?? d.dxvkHUD
        retinaMode = try c.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? d.retinaMode
        commandAsControl = try c.decodeIfPresent(Bool.self, forKey: .commandAsControl) ?? d.commandAsControl
        verboseLogging = try c.decodeIfPresent(Bool.self, forKey: .verboseLogging) ?? d.verboseLogging
        dllOverrides = try c.decodeIfPresent(String.self, forKey: .dllOverrides) ?? d.dllOverrides
        environment = try c.decodeIfPresent([EnvironmentVariable].self, forKey: .environment) ?? d.environment
    }
}

/// A program the user pinned to a bottle.
struct PinnedProgram: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// Unix path of the .exe / .lnk / .msi / .bat inside (or outside) the bottle.
    var path: String
    var arguments: String = ""

    var url: URL { URL(fileURLWithPath: path) }
}

/// A Wine prefix plus Crossway's metadata about it (CrossOver calls these "bottles").
struct Bottle: Identifiable, Hashable, Codable {
    static let metadataFile = "crossway-bottle.json"

    var id: UUID
    var name: String
    var runtimeID: String
    var created: Date
    var settings: BottleSettings
    var programs: [PinnedProgram]

    /// The WINEPREFIX. Not persisted — derived from where the metadata file lives.
    var url: URL = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey {
        case id, name, runtimeID, created, settings, programs
    }

    init(id: UUID = UUID(), name: String, runtimeID: String, settings: BottleSettings, url: URL) {
        self.id = id
        self.name = name
        self.runtimeID = runtimeID
        self.created = Date()
        self.settings = settings
        self.programs = []
        self.url = url
    }

    var driveC: URL { url.appendingPathComponent("drive_c", isDirectory: true) }
    var metadataURL: URL { url.appendingPathComponent(Bottle.metadataFile) }
    var isInitialized: Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent("system.reg").path) }

    var logsDirectory: URL { Paths.logs.appendingPathComponent(id.uuidString, isDirectory: true) }

    /// Converts a Windows path (C:\Program Files\...) inside this bottle to a Unix path.
    func unixPath(forWindowsPath windowsPath: String) -> URL {
        var path = windowsPath.replacingOccurrences(of: "\\", with: "/")
        if path.lowercased().hasPrefix("c:") { path.removeFirst(2) }
        return driveC.appendingPathComponent(path)
    }

    /// Converts a Unix path inside drive_c to a Windows path.
    func windowsPath(for url: URL) -> String? {
        let base = driveC.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target.hasPrefix(base) else { return nil }
        let rest = target.dropFirst(base.count).replacingOccurrences(of: "/", with: "\\")
        return "C:" + (rest.isEmpty ? "\\" : rest)
    }
}

enum BottleIO {
    static func loadAll() -> [Bottle] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: Paths.bottles, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap(load(at:)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func load(at directory: URL) -> Bottle? {
        let url = directory.appendingPathComponent(Bottle.metadataFile)
        guard let data = try? Data(contentsOf: url),
              var bottle = try? JSONDecoder.crossway.decode(Bottle.self, from: data) else { return nil }
        bottle.url = directory
        return bottle
    }

    static func save(_ bottle: Bottle) throws {
        try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        let data = try JSONEncoder.crossway.encode(bottle)
        try data.write(to: bottle.metadataURL, options: .atomic)
    }
}
