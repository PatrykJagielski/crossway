import SwiftUI
import UniformTypeIdentifiers

struct BottleDetailView: View {
    let bottleID: UUID
    var initialTab: Tab = .programs

    enum Tab: String, CaseIterable, Identifiable {
        case programs = "Programy"
        case install = "Instaluj"
        case settings = "Ustawienia"
        case logs = "Logi"
        var id: String { rawValue }
    }

    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var runner: WineRunner
    @EnvironmentObject private var runtimes: RuntimeManager
    @State private var tab: Tab = .programs
    @State private var appliedInitialTab = false
    @State private var error: String?

    var body: some View {
        if let bottle = bottles.bottle(id: bottleID) {
            VStack(spacing: 0) {
                header(bottle)
                Divider()
                switch tab {
                case .programs: ProgramsView(bottle: bottle)
                case .install: InstallView(bottle: bottle)
                case .settings: BottleSettingsView(bottle: bottle)
                case .logs: LogsView(bottle: bottle)
                }
            }
            .navigationTitle(bottle.name)
            .onAppear {
                if !appliedInitialTab { tab = initialTab; appliedInitialTab = true }
            }
            .toolbar { toolbar(bottle) }
            .alert("Błąd", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func header(_ bottle: Bottle) -> some View {
        let runtime = runtimes.runtime(id: bottle.runtimeID)
        let processes = runner.running(in: bottle)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "wineglass.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(bottle.name).font(.title2.bold())
                    HStack(spacing: 6) {
                        Tag(text: bottle.settings.windowsVersion.title, symbol: "pc")
                        Tag(text: runtime?.name ?? "Brak środowiska", symbol: "shippingbox", warning: runtime == nil)
                        Tag(text: graphicsLabel(bottle, runtime), symbol: "cpu")
                    }
                }
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 330)
            }

            if let busy = bottles.busy[bottle.id] {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.callout).foregroundStyle(.secondary)
                }
            }

            if !processes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(processes) { process in
                            HStack(spacing: 6) {
                                Circle().fill(.green).frame(width: 7, height: 7)
                                Text(process.name).lineLimit(1)
                                Text(process.started, style: .timer)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button {
                                    runner.stop(process)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .help("Zatrzymaj")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func graphicsLabel(_ bottle: Bottle, _ runtime: WineRuntime?) -> String {
        guard let runtime else { return "—" }
        let backend = WineLauncher.effectiveBackend(bottle.settings, runtime: runtime)
        if backend == .d3dmetal, let version = runtime.d3dMetalVersion { return "D3DMetal \(version)" }
        return backend.shortTitle
    }

    @ToolbarContentBuilder
    private func toolbar(_ bottle: Bottle) -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                runFile(in: bottle)
            } label: {
                Label("Uruchom plik…", systemImage: "play.fill")
            }
            .help("Uruchom plik .exe, .msi lub .bat w tej butelce")

            Button {
                NSWorkspace.shared.open(bottle.driveC)
            } label: {
                Label("Dysk C:", systemImage: "internaldrive")
            }
            .help("Otwórz dysk C: w Finderze")

            Menu {
                Button("Konfiguracja Wine (winecfg)") { tool(["winecfg"], "winecfg", bottle) }
                Button("Edytor rejestru") { tool(["regedit"], "regedit", bottle) }
                Button("Menedżer zadań") { tool(["taskmgr"], "taskmgr", bottle) }
                Button("Wiersz poleceń") { tool(["start", "cmd"], "cmd", bottle) }
                Button("Panel sterowania") { tool(["control"], "control", bottle) }
                Button("Eksplorator plików") { tool(["explorer"], "explorer", bottle) }
                Button("Odinstaluj programy…") { tool(["uninstaller"], "uninstaller", bottle) }
                Divider()
                Button("Symuluj restart Windows") { tool(["wineboot", "--restart"], "wineboot", bottle) }
                Button("Zakończ wszystkie procesy", role: .destructive) {
                    if let runtime = try? bottles.runtime(for: bottle) { runner.killAll(in: bottle, runtime: runtime) }
                }
            } label: {
                Label("Narzędzia", systemImage: "wrench.and.screwdriver")
            }
            .help("Narzędzia Windows w tej butelce")
        }
    }

    private func tool(_ args: [String], _ name: String, _ bottle: Bottle) {
        do {
            try runner.launchTool(args, name: name, in: bottle, runtime: bottles.runtime(for: bottle))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runFile(in bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = WindowsFileTypes.all
        panel.allowsOtherFileTypes = true
        panel.message = "Wybierz program lub instalator Windows"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try runner.launch(file: url, in: bottle, runtime: bottles.runtime(for: bottle))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum WindowsFileTypes {
    static let all: [UTType] = ["exe", "msi", "bat", "cmd", "lnk", "com"]
        .compactMap { UTType(filenameExtension: $0) }
}

struct Tag: View {
    let text: String
    let symbol: String
    var warning = false

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(warning ? AnyShapeStyle(.orange.opacity(0.2)) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(warning ? .orange : .secondary)
    }
}
