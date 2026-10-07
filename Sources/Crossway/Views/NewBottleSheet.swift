import SwiftUI
import UniformTypeIdentifiers

struct NewBottleSheet: View {
    var onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var runtimes: RuntimeManager

    @State private var name = "Gry"
    @State private var runtimeID = ""
    @State private var settings = BottleSettings()
    @State private var creating = false

    private var runtime: WineRuntime? { runtimes.runtime(id: runtimeID) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Nazwa", text: $name)
                    Picker("Środowisko Wine", selection: $runtimeID) {
                        ForEach(runtimes.runtimes) { runtime in
                            Text("\(runtime.name) — \(runtime.graphicsSummary)").tag(runtime.id)
                        }
                    }
                    Picker("Wersja Windows", selection: $settings.windowsVersion) {
                        ForEach(WindowsVersion.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Nowa butelka")
                } footer: {
                    Text("Każda butelka to oddzielna instalacja Windows (prefiks Wine). Zwykle wystarczy jedna na launcher, np. „Steam”.")
                }

                Section("Grafika") {
                    GraphicsPicker(settings: $settings, runtime: runtime)
                }
            }
            .formStyle(.grouped)
            .disabled(creating)

            Divider()
            HStack {
                if creating, let busy = bottles.busy.values.first {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(creating)
                Button("Utwórz") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(creating || runtime == nil)
            }
            .padding()
        }
        .frame(width: 520, height: 470)
        .onAppear {
            runtimeID = runtimes.defaultRuntime?.id ?? runtimes.runtimes.first?.id ?? ""
        }
    }

    private func create() {
        guard let runtime else { return }
        creating = true
        Task {
            let bottle = await bottles.create(name: name, runtime: runtime, settings: settings)
            creating = false
            if let bottle { onCreated(bottle.id) }
            dismiss()
        }
    }
}

/// Graphics backend selector shared by "new bottle" and bottle settings.
struct GraphicsPicker: View {
    @Binding var settings: BottleSettings
    let runtime: WineRuntime?

    var body: some View {
        Picker("Tłumaczenie DirectX", selection: $settings.graphics) {
            Text(runtime?.hasD3DMetal == true ? "D3DMetal (DirectX 11/12 → Metal)" : "WineD3D (wbudowany)")
                .tag(GraphicsBackend.automatic)
            Text("DXVK (DirectX 9–11 → Vulkan → Metal)").tag(GraphicsBackend.dxvk)
                .selectionDisabled(runtime?.hasVulkan != true)
        }
        .onChange(of: runtime?.id) {
            if runtime?.hasVulkan != true { settings.graphics = .automatic }
        }
        if runtime?.hasVulkan != true {
            Text("To środowisko nie ma Vulkana — DXVK jest niedostępny.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if settings.graphics == .automatic, runtime?.hasD3DMetal == true {
            Text("Zalecane dla gier DX11/DX12. Gry DX9 korzystają z WineD3D.")
                .font(.caption).foregroundStyle(.secondary)
        } else if settings.graphics == .dxvk {
            Text("Dobre dla starszych gier DX9–DX11. Wymaga pobrania DXVK w oknie Środowiska.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Shown when a .exe/.msi is opened from Finder: pick a bottle to run it in.
struct OpenFileSheet: View {
    let file: URL

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var runner: WineRunner
    @State private var bottleID: UUID?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(file.lastPathComponent, systemImage: "doc.fill")
                .font(.headline)
            if bottles.bottles.isEmpty {
                Text("Najpierw utwórz butelkę.").foregroundStyle(.secondary)
            } else {
                Picker("Uruchom w butelce", selection: $bottleID) {
                    ForEach(bottles.bottles) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Anuluj") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Uruchom") { run() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(bottleID == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { bottleID = state.selection ?? bottles.bottles.first?.id }
    }

    private func run() {
        guard let bottle = bottles.bottle(id: bottleID) else { return }
        do {
            let runtime = try bottles.runtime(for: bottle)
            try runner.launch(file: file, in: bottle, runtime: runtime)
            state.selection = bottle.id
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
