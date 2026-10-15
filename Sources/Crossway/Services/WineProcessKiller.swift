import Foundation

/// Last-resort cleanup for Wine processes that `wineserver -k` cannot reach — e.g. when
/// the wineserver itself died and left Windows programs (Steam's webhelper, services.exe…)
/// orphaned. Wine renames its processes after the Windows executable ("C:\…\x.exe").
enum WineProcessKiller {
    struct Candidate {
        let pid: Int32
        let command: String
    }

    /// Every process that looks like a Wine process.
    static func wineProcesses() -> [Candidate] {
        guard let output = run("/bin/ps", ["-Ao", "pid=,command="]) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { return nil }
            let command = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
            let isWindowsProgram = command.range(of: #"^[A-Za-z]:\\"#, options: .regularExpression) != nil
            // Programs Crossway starts by Unix path keep it as their name (…/Bottles/…/x.exe).
            let isWine = command == "(wine)" || command.contains("/Crossway/Runtimes/") || command.contains("/Crossway/Bottles/")
            return (isWindowsProgram || isWine) && pid != getpid() ? Candidate(pid: pid, command: command) : nil
        }
    }

    /// True when the process runs the given executable, whether Wine shows it as
    /// `C:\…\name.exe` or as the Unix path it was started with.
    static func command(_ command: String, runs exe: String) -> Bool {
        let normalized = command.lowercased().replacingOccurrences(of: "/", with: "\\")
        return normalized.contains("\\" + exe.lowercased())
    }

    /// Wine processes that hold files open inside `bottle` (its prefix is their WINEPREFIX).
    static func processes(in bottle: Bottle) -> [Candidate] {
        let prefix = bottle.url.standardizedFileURL.path
        return wineProcesses().filter { candidate in
            guard let files = run("/usr/sbin/lsof", ["-Fn", "-p", String(candidate.pid)]) else { return false }
            return files.contains(prefix)
        }
    }

    /// SIGKILL, then wait briefly: under Rosetta exiting can take a few seconds.
    @discardableResult
    static func kill(_ candidates: [Candidate]) -> Int {
        for candidate in candidates { Darwin.kill(candidate.pid, SIGKILL) }
        for _ in 0..<20 where candidates.contains(where: { Darwin.kill($0.pid, 0) == 0 }) {
            Thread.sleep(forTimeInterval: 0.25)
        }
        return candidates.count
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
