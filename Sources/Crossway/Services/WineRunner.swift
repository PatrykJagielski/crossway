import Foundation
import AppKit

enum CrosswayError: LocalizedError {
    case runtimeMissing(String)
    case processFailed(String, Int32)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing(let id):
            return "Nie znaleziono środowiska Wine „\(id)”. Wybierz inne w ustawieniach butelki lub pobierz je w oknie Środowiska."
        case .processFailed(let what, let code):
            return "\(what) zakończył się kodem \(code). Szczegóły w logach butelki."
        case .message(let text):
            return text
        }
    }
}

/// Starts Wine processes and keeps track of the ones that are running.
@MainActor
final class WineRunner: ObservableObject {
    struct RunningProcess: Identifiable {
        let id = UUID()
        let bottleID: UUID
        let name: String
        let started = Date()
        let logURL: URL
        let process: Process
    }

    @Published private(set) var running: [RunningProcess] = []

    func running(in bottle: Bottle) -> [RunningProcess] {
        running.filter { $0.bottleID == bottle.id }
    }

    /// Launches a Windows program (exe/msi/lnk/bat) without waiting for it.
    @discardableResult
    func launch(file original: URL, arguments originalArguments: String = "", name: String? = nil, in bottle: Bottle, runtime: WineRuntime) throws -> RunningProcess {
        let (url, arguments) = SteamFix.prepare(file: original, arguments: originalArguments, in: bottle)
        let args = WineLauncher.wineArguments(forFile: url, extraArguments: WineLauncher.splitArguments(arguments))
        let label = name ?? original.deletingPathExtension().lastPathComponent
        return try start(arguments: args, name: label, workingDirectory: url.deletingLastPathComponent(), bottle: bottle, runtime: runtime)
    }

    /// Launches a Wine built-in tool such as `winecfg`, `regedit` or `taskmgr`.
    @discardableResult
    func launchTool(_ arguments: [String], name: String, in bottle: Bottle, runtime: WineRuntime) throws -> RunningProcess {
        try start(arguments: arguments, name: name, workingDirectory: nil, bottle: bottle, runtime: runtime)
    }

    /// Runs Wine and waits for it to exit. Used for wineboot, reg, installers...
    func runAndWait(_ arguments: [String], name: String, workingDirectory: URL? = nil, in bottle: Bottle, runtime: WineRuntime) async throws -> Int32 {
        let entry = try start(arguments: arguments, name: name, workingDirectory: workingDirectory, bottle: bottle, runtime: runtime)
        return await Self.waitForExit(entry.process)
    }

    /// `wineserver -k`: kills every Windows process in the bottle.
    func killAll(in bottle: Bottle, runtime: WineRuntime) {
        let process = Process()
        process.executableURL = runtime.wineserver
        process.arguments = ["-k"]
        process.environment = WineLauncher.environment(bottle: bottle, runtime: runtime)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        for entry in running(in: bottle) where entry.process.isRunning {
            entry.process.terminate()
        }
        // If the wineserver had already died, `-k` reaches nothing: kill leftovers directly.
        let snapshot = bottle
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
            WineProcessKiller.kill(WineProcessKiller.processes(in: snapshot))
        }
    }

    /// Emergency stop for every Windows program, in every bottle.
    func forceQuitEverything() async -> Int {
        for entry in running where entry.process.isRunning { entry.process.terminate() }
        return await Task.detached(priority: .userInitiated) {
            WineProcessKiller.kill(WineProcessKiller.wineProcesses())
        }.value
    }

    /// Waits until the bottle's wineserver exits (all programs closed, registry flushed).
    func waitForWineserver(in bottle: Bottle, runtime: WineRuntime) async {
        let process = Process()
        process.executableURL = runtime.wineserver
        process.arguments = ["-w"]
        process.environment = WineLauncher.environment(bottle: bottle, runtime: runtime)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        _ = await Self.waitForExit(process)
    }

    func stop(_ entry: RunningProcess) {
        if entry.process.isRunning { entry.process.terminate() }
    }

    private func start(arguments: [String], name: String, workingDirectory: URL?, bottle: Bottle, runtime: WineRuntime) throws -> RunningProcess {
        guard Paths.rosettaInstalled else {
            throw CrosswayError.message("Rosetta 2 nie jest zainstalowana. Wine dla macOS to aplikacja x86_64 — zainstaluj Rosettę (Ustawienia → Środowiska).")
        }
        let logURL = WineLauncher.newLogURL(bottle: bottle, label: name)
        let process = try WineLauncher.makeProcess(
            bottle: bottle, runtime: runtime, arguments: arguments,
            workingDirectory: workingDirectory, logURL: logURL
        )
        let entry = RunningProcess(bottleID: bottle.id, name: name, logURL: logURL, process: process)
        let entryID = entry.id
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.running.removeAll { $0.id == entryID } }
        }
        try process.run()
        running.append(entry)
        return entry
    }

    nonisolated static func waitForExit(_ process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }
}
