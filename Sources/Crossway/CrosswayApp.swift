import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    let runner: WineRunner
    let runtimes: RuntimeManager
    let bottles: BottleManager
    let installs: InstallManager

    @Published var selection: UUID?
    /// A Windows file opened from Finder ("Open With…" / drag onto the Dock icon).
    @Published var pendingOpenFile: URL?
    @Published var showRuntimes = false
    @Published var showNewBottle = false

    init() {
        runner = WineRunner()
        runtimes = RuntimeManager()
        bottles = BottleManager(runner: runner, runtimes: runtimes)
        installs = InstallManager(bottles: bottles, runtimes: runtimes)
        selection = bottles.bottles.first?.id
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpen: ((URL) -> Void)?
    private var queued: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let onOpen else { queued.append(contentsOf: urls); return }
        urls.forEach(onOpen)
    }

    func flush() {
        guard let onOpen else { return }
        queued.forEach(onOpen)
        queued.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct CrosswayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Crossway", id: "main") {
            ContentView()
                .environmentObject(state)
                .environmentObject(state.runner)
                .environmentObject(state.runtimes)
                .environmentObject(state.bottles)
                .environmentObject(state.installs)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    delegate.onOpen = { url in state.pendingOpenFile = url }
                    delegate.flush()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nowa butelka…") { state.showNewBottle = true }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .appSettings) {
                Button("Środowiska Wine…") { state.showRuntimes = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            RuntimesView()
                .environmentObject(state.runtimes)
                .frame(width: 720, height: 560)
        }
    }
}
