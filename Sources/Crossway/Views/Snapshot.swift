import SwiftUI
import AppKit

/// Developer aid: `Crossway --cli snapshot <out.png> [programs|install|settings|logs|runtimes|new]`
/// renders the main window off-screen, so the UI can be checked without clicking through it.
enum Snapshot {
    @MainActor
    static func render(to path: String, view name: String) async -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let state = AppState()
        let root: AnyView
        switch name {
        case "runtimes":
            root = AnyView(VStack(spacing: 0) { Text("Środowiska Wine").font(.title2.bold()).padding(); Divider(); RuntimesView() })
        case "new":
            root = AnyView(NewBottleSheet { _ in })
        default:
            let tab = BottleDetailView.Tab.allCases.first { "\($0)" == name } ?? .programs
            root = AnyView(SnapshotMain(initialTab: tab))
        }
        let content = root
            .environmentObject(state)
            .environmentObject(state.runner)
            .environmentObject(state.runtimes)
            .environmentObject(state.bottles)
            .environmentObject(state.installs)
            .frame(width: name == "new" ? 520 : 1100, height: name == "new" ? 470 : 720)

        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1100, height: 720),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: content)
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.close()
        return 0
    }
}

private struct SnapshotMain: View {
    let initialTab: BottleDetailView.Tab
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            ContentViewSidebarProxy()
        } detail: {
            if let id = state.selection {
                BottleDetailView(bottleID: id, initialTab: initialTab)
            } else {
                WelcomeView()
            }
        }
    }
}

private struct ContentViewSidebarProxy: View {
    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var state: AppState
    var body: some View {
        List(selection: $state.selection) {
            Section("Butelki") {
                ForEach(bottles.bottles) { Label($0.name, systemImage: "wineglass.fill").tag($0.id) }
            }
        }
        .listStyle(.sidebar)
    }
}
