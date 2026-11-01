import Foundation

/// Wired third-party Xbox controllers (Turtle Beach, PDP, PowerA…) speak Microsoft's GIP
/// protocol over USB and macOS has no driver for them, so Wine never sees them. Wine's winebus
/// reads controllers through SDL; Crossway ships an SDL 3 built with libusb (see
/// scripts/build-usb-gamepads.sh) that talks to such controllers directly, and puts it in
/// front of the runtime's own SDL when a bottle starts.
enum UsbGamepads {
    static let sdlName = "libSDL3.dylib"
    static let libusbName = "libusb-1.0.0.dylib"
    /// The runtime's sdl2-compat (what winebus loads); it picks up SDL 3 from its own folder.
    static let sdl2Name = "libSDL2-2.0.0.dylib"

    /// Shipped libraries: in the app bundle, or next to the sources during development.
    static var bundledDirectory: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("UsbGamepads", isDirectory: true),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/UsbGamepads", isDirectory: true),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(sdlName).path)
        }
    }

    /// Folder to put first on DYLD_FALLBACK_LIBRARY_PATH for this runtime, or nil when the
    /// runtime has no SDL for winebus or the libraries are missing. sdl2-compat loads SDL 3 from
    /// `@loader_path`, so all three libraries must sit together: a per-runtime folder holding
    /// the runtime's sdl2-compat next to our SDL 3 and libusb.
    static func libraryDirectory(for runtime: WineRuntime) -> URL? {
        guard let source = bundledDirectory, let frameworks = runtime.frameworks else { return nil }
        let sdl2 = frameworks.appendingPathComponent(sdl2Name)
        guard FileManager.default.fileExists(atPath: sdl2.path) else { return nil }

        let target = Paths.components.appendingPathComponent("UsbGamepads/\(runtime.id)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try copyIfChanged(sdl2, to: target.appendingPathComponent(sdl2Name))
            try copyIfChanged(source.appendingPathComponent(sdlName), to: target.appendingPathComponent(sdlName))
            try copyIfChanged(source.appendingPathComponent(libusbName), to: target.appendingPathComponent(libusbName))
        } catch {
            return nil
        }
        return target
    }

    /// Environment changes for a bottle with USB controllers enabled.
    static func apply(to env: inout [String: String], runtime: WineRuntime) {
        guard let directory = libraryDirectory(for: runtime) else { return }
        let rest = env["DYLD_FALLBACK_LIBRARY_PATH"].map { ":" + $0 } ?? ""
        env["DYLD_FALLBACK_LIBRARY_PATH"] = directory.path + rest
        // By default SDL on macOS uses libusb only for a short list of devices; let it reach
        // every controller that has no system driver.
        env["SDL_HIDAPI_LIBUSB_WHITELIST"] = "0"
    }

    private static func copyIfChanged(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        func stamp(_ url: URL) -> [AnyHashable]? {
            guard let a = try? fm.attributesOfItem(atPath: url.path) else { return nil }
            return [a[.size] as? NSNumber, a[.modificationDate] as? Date].compactMap { $0 as? AnyHashable }
        }
        if let s = stamp(source), s == stamp(target) { return }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: source, to: target) // keeps the modification date
    }
}
