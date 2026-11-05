import Foundation

/// Caps the size of Wine logs. A hung game can print the same error thousands of times
/// a second for days (e.g. `err:msync` after wineserver died), which once filled 240 GB.
///
/// Wine's output goes through a pipe to a helper process (`Crossway --log-sink <log>`),
/// not to the app itself: Steam started from a shortcut outlives the shortcut and the app.
/// The helper keeps the first `headLimit` bytes in the log; everything after that goes to
/// `<name>.koniec.log`, which is emptied whenever it reaches `tailLimit`, so it always holds
/// the latest output. It exits when the last Wine process holding the pipe closes it.
enum LogSink {
    static let headLimit = 64 << 20
    static let tailLimit = 16 << 20

    /// `Crossway --log-sink <log> [headMB] [tailMB]` — reads stdin until EOF.
    static func handle(_ arguments: [String]) -> Int32? {
        guard arguments.count >= 3, arguments[1] == "--log-sink" else { return nil }
        let head = arguments.count > 3 ? (Int(arguments[3]) ?? 0) << 20 : headLimit
        let tail = arguments.count > 4 ? (Int(arguments[4]) ?? 0) << 20 : tailLimit
        return run(log: URL(fileURLWithPath: arguments[2]), headLimit: max(head, 1 << 20), tailLimit: max(tail, 1 << 20))
    }

    /// Points the process's stdout and stderr at a new sink appending to `logURL`.
    /// Falls back to writing the file directly if the helper cannot start.
    static func attach(to process: Process, logURL: URL) throws {
        if let executable = Bundle.main.executableURL {
            let pipe = Pipe()
            let sink = Process()
            sink.executableURL = executable
            sink.arguments = ["--log-sink", logURL.path]
            // Launching closes our copy of the read end; the write end is closed when
            // `process` launches, so the sink sees EOF once Wine and its children are gone.
            sink.standardInput = pipe
            sink.standardOutput = FileHandle.nullDevice
            sink.standardError = FileHandle.nullDevice
            if (try? sink.run()) != nil {
                process.standardOutput = pipe
                process.standardError = pipe
                return
            }
        }
        let handle = try FileHandle(forWritingTo: logURL)
        handle.seekToEndOfFile()
        process.standardOutput = handle
        process.standardError = handle
    }

    static func tailURL(for log: URL) -> URL {
        log.deletingPathExtension().appendingPathExtension("koniec.log")
    }

    private static func run(log: URL, headLimit: Int, tailLimit: Int) -> Int32 {
        // Keep draining the pipe when the app or terminal goes away, so Wine never blocks on a full pipe.
        signal(SIGHUP, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)

        let main = open(log.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        var tail: Int32 = -1
        var total = 0
        var tailSize = 0
        let tailName = tailURL(for: log).lastPathComponent

        func write(_ fd: Int32, _ text: String) {
            guard fd >= 0 else { return }
            var bytes = Array(text.utf8)
            _ = bytes.withUnsafeMutableBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        }

        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { break }
            buffer.withUnsafeBytes { raw in
                var chunk = UnsafeRawBufferPointer(rebasing: raw[0..<n])
                if total < headLimit {
                    let room = min(chunk.count, headLimit - total)
                    if main >= 0 { _ = Darwin.write(main, chunk.baseAddress, room) }
                    total += room
                    chunk = UnsafeRawBufferPointer(rebasing: chunk[room...])
                    if total >= headLimit {
                        write(main, "\n[Crossway] Log osiągnął \(headLimit >> 20) MB — dalsze wyjście trafia do \(tailName) (tylko ostatnie ~\(tailLimit >> 20) MB).\n")
                        tail = open(tailURL(for: log).path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
                    }
                }
                guard !chunk.isEmpty else { return }
                total += chunk.count
                if tailSize + chunk.count > tailLimit, tail >= 0 {
                    ftruncate(tail, 0)
                    lseek(tail, 0, SEEK_SET)
                    tailSize = 0
                    write(tail, "[Crossway] Starsza część pominięta — łącznie \(total >> 20) MB wyjścia.\n")
                }
                if tail >= 0 { _ = Darwin.write(tail, chunk.baseAddress, chunk.count) }
                tailSize += chunk.count
            }
        }
        if total > headLimit {
            write(main, "[Crossway] Koniec: łącznie \(total >> 20) MB wyjścia.\n")
        }
        if tail >= 0 { close(tail) }
        if main >= 0 { close(main) }
        return 0
    }
}
