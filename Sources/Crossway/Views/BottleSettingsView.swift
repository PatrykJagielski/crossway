import SwiftUI

struct BottleSettingsView: View {
    let bottle: Bottle

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var runtimes: RuntimeManager
    @State private var draft: Bottle
    @State private var confirmDelete = false

    init(bottle: Bottle) {
        self.bottle = bottle
        _draft = State(initialValue: bottle)
    }

    private var runtime: WineRuntime? { runtimes.runtime(id: draft.runtimeID) }
    private var changed: Bool { draft != bottle }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Ogólne") {
                    TextField("Nazwa", text: $draft.name)
                    Picker("Środowisko Wine", selection: $draft.runtimeID) {
                        if runtimes.runtime(id: draft.runtimeID) == nil {
                            Text("Brak (\(draft.runtimeID))").tag(draft.runtimeID)
                        }
                        ForEach(runtimes.runtimes) { Text("\($0.name) — \($0.graphicsSummary)").tag($0.id) }
                    }
                    Picker("Wersja Windows", selection: $draft.settings.windowsVersion) {
                        ForEach(WindowsVersion.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section("Grafika") {
                    GraphicsPicker(settings: $draft.settings, runtime: runtime)
                    Toggle("Metal Performance HUD (FPS, czas klatki, GPU)", isOn: $draft.settings.metalHUD)
                    if let runtime, WineLauncher.effectiveBackend(draft.settings, runtime: runtime) == .d3dmetal {
                        Toggle("Ray tracing DirectX (DXR) — M3 i nowsze", isOn: $draft.settings.raytracing)
                        Toggle("DLSS → MetalFX (eksperymentalne)", isOn: $draft.settings.metalFX)
                            .disabled(runtime.hasMetalFXShim != true)
                    }
                    if let runtime, WineLauncher.effectiveBackend(draft.settings, runtime: runtime) == .dxvk {
                        Toggle("DXVK async (mniej przycięć przy kompilacji shaderów)", isOn: $draft.settings.dxvkAsync)
                        Toggle("Nakładka DXVK HUD", isOn: $draft.settings.dxvkHUD)
                    }
                }

                Section("Wydajność") {
                    Picker("Synchronizacja", selection: $draft.settings.sync) {
                        ForEach(SyncMode.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Udostępniaj AVX/AVX2 grom (Rosetta)", isOn: $draft.settings.advertiseAVX)
                    Text("Wiele nowych gier wymaga AVX. Rosetta na macOS 15+ obsługuje AVX2.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Ekran i klawiatura") {
                    Toggle("Tryb Retina (pełna rozdzielczość)", isOn: $draft.settings.retinaMode)
                    Toggle("⌘ Command działa jak Ctrl", isOn: $draft.settings.commandAsControl)
                }

                Section {
                    Toggle("Szczegółowe logi (wolniej)", isOn: $draft.settings.verboseLogging)
                    TextField("Nadpisania DLL", text: $draft.settings.dllOverrides, prompt: Text("np. dinput8=n,b;xinput1_3=n,b"))
                    ForEach($draft.settings.environment) { $variable in
                        HStack {
                            TextField("ZMIENNA", text: $variable.key).font(.body.monospaced())
                            Text("=")
                            TextField("wartość", text: $variable.value).font(.body.monospaced())
                            Button {
                                draft.settings.environment.removeAll { $0.id == variable.id }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Dodaj zmienną środowiskową") {
                        draft.settings.environment.append(EnvironmentVariable(key: "", value: ""))
                    }
                } header: {
                    Text("Zaawansowane")
                }

                Section("Butelka") {
                    LabeledContent("Lokalizacja") {
                        Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([bottle.url]) }
                    }
                    LabeledContent("Utworzona") { Text(bottle.created, style: .date) }
                    Button("Duplikuj butelkę") { Task { await bottles.duplicate(bottle) } }
                    Button("Usuń butelkę…", role: .destructive) { confirmDelete = true }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if changed { Text("Niezapisane zmiany").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Przywróć") { draft = bottle }.disabled(!changed)
                Button("Zapisz") {
                    let previous = bottle
                    let updated = draft
                    Task { await bottles.update(updated, previous: previous) }
                }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!changed || bottles.busy[bottle.id] != nil)
            }
            .padding(12)
        }
        .onChange(of: bottle) { old, new in
            // Follow changes made elsewhere (pinned programs, saves) without dropping unsaved edits.
            var untouched = draft
            untouched.programs = old.programs
            if untouched == old { draft = new } else { draft.programs = new.programs }
        }
        .confirmationDialog("Usunąć butelkę „\(bottle.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Przenieś do Kosza", role: .destructive) {
                state.selection = nil
                bottles.delete(bottle)
            }
        } message: {
            Text("Wszystkie programy i zapisy gier w tej butelce trafią do Kosza.")
        }
    }
}
