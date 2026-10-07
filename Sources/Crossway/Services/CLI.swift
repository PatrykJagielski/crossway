import Foundation

/// `Crossway --cli <command>` — scriptable access to the same managers the UI uses.
///   runtimes                         list runtimes
///   download <gptk|wine-staging|wine-devel|dxvk>
///   bottles                          list bottles
///   create <name> [runtime-id]       create a bottle
///   run <bottle-name-or-id> <file> [args…]   run a Windows program and wait
enum CLI {
    static func handle(_ arguments: [String]) -> Int32? {
        guard arguments.count >= 2, arguments[1] == "--cli" else { return nil }
        let args = Array(arguments.dropFirst(2))
        var code: Int32 = 0
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            code = await run(args)
            done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return code
    }

    @MainActor
    private static func run(_ args: [String]) async -> Int32 {
        let runner = WineRunner()
        let runtimes = RuntimeManager()
        let bottles = BottleManager(runner: runner, runtimes: runtimes)

        switch args.first {
        case "runtimes":
            for r in runtimes.runtimes {
                print("\(r.id)\t\(r.name)\t\(r.version)\t\(r.graphicsSummary)")
            }
            return 0

        case "download":
            guard args.count > 1, let offer = DownloadOffer.all.first(where: { $0.id == args[1] }) else {
                print("Dostępne: " + DownloadOffer.all.map(\.id).joined(separator: ", "))
                return 64
            }
            let watcher = Task { @MainActor in
                var last = ""
                while !Task.isCancelled {
                    if let p = runtimes.progress[offer.id], p.message != last {
                        last = p.message
                        print(p.message)
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            await runtimes.install(offer)
            watcher.cancel()
            if let error = runtimes.lastError { print("Błąd: \(error)"); return 1 }
            print("Zainstalowano \(offer.title)")
            return 0

        case "bottles":
            for b in bottles.bottles {
                print("\(b.id.uuidString)\t\(b.name)\t\(b.runtimeID)\t\(b.url.path)")
            }
            return 0

        case "create":
            guard args.count > 1 else { print("Użycie: create <nazwa> [runtime-id]"); return 64 }
            guard let runtime = args.count > 2 ? runtimes.runtime(id: args[2]) : runtimes.defaultRuntime else {
                print("Brak środowiska Wine — użyj: download gptk"); return 1
            }
            let start = Date()
            guard let bottle = await bottles.create(name: args[1], runtime: runtime, settings: BottleSettings()) else { return 1 }
            if let error = bottles.lastError { print("Błąd: \(error)"); return 1 }
            print("Utworzono \(bottle.name) (\(bottle.id.uuidString)) w \(Int(Date().timeIntervalSince(start))) s")
            print(bottle.url.path)
            return 0

        case "run":
            guard args.count > 2 else { print("Użycie: run <butelka> <plik> [argumenty…]"); return 64 }
            guard let bottle = bottles.bottles.first(where: { $0.name == args[1] || $0.id.uuidString == args[1] }) else {
                print("Nie ma butelki \(args[1])"); return 1
            }
            do {
                let runtime = try bottles.runtime(for: bottle)
                let path = args[2]
                // Plain names (cmd, winecfg…) are Wine builtins; anything else is a file.
                let wineArgs = path.contains("/")
                    ? WineLauncher.wineArguments(forFile: URL(fileURLWithPath: path), extraArguments: Array(args.dropFirst(3)))
                    : Array(args.dropFirst(2))
                let code = try await runner.runAndWait(wineArgs, name: URL(fileURLWithPath: path).lastPathComponent, in: bottle, runtime: runtime)
                if let log = runner.running.last?.logURL ?? latestLog(bottle) { print("Log: \(log.path)") }
                return code
            } catch {
                print("Błąd: \(error.localizedDescription)"); return 1
            }

        case "snapshot":
            return await Snapshot.render(to: args.count > 1 ? args[1] : "snapshot.png", view: args.count > 2 ? args[2] : "programs")

        default:
            print("Polecenia: runtimes | download <id> | bottles | create <nazwa> [runtime] | run <butelka> <plik|polecenie> [argumenty]")
            return 64
        }
    }

    private static func latestLog(_ bottle: Bottle) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: bottle.logsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }
}
