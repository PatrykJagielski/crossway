import Foundation

/// Downloads a file with progress reporting.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private let destination: URL
    private let progress: @Sendable (Double, Int64, Int64) -> Void
    private var session: URLSession?

    private init(destination: URL, progress: @escaping @Sendable (Double, Int64, Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    /// Downloads `url` to `destination`, calling `progress(fraction, written, total)` along the way.
    static func download(
        _ url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double, Int64, Int64) -> Void
    ) async throws -> URL {
        let downloader = Downloader(destination: destination, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                downloader.continuation = continuation
                let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
                downloader.session = session
                var request = URLRequest(url: url)
                request.setValue("Crossway/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            downloader.session?.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        progress(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw CrosswayError.message("Serwer zwrócił błąd HTTP \(http.statusCode) dla \(downloadTask.originalRequest?.url?.absoluteString ?? "")")
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

enum Shell {
    /// Runs a command-line tool and returns its exit code and combined output.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        let code = await WineRunner.waitForExit(process)
        return (code, String(decoding: data, as: UTF8.self))
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
