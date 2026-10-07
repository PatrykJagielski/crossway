import SwiftUI

/// Manage Wine runtimes and shared components (DXVK, winetricks).
struct RuntimesView: View {
    @EnvironmentObject private var runtimes: RuntimeManager
    @State private var runtimeToDelete: WineRuntime?

    var body: some View {
        Form {
            Section("Zainstalowane środowiska") {
                if runtimes.runtimes.isEmpty {
                    Text("Brak środowisk — pobierz jedno poniżej.")
                        .foregroundStyle(.secondary)
                }
                ForEach(runtimes.runtimes) { runtime in
                    HStack(alignment: .top) {
                        Image(systemName: runtime.hasD3DMetal ? "cpu.fill" : "cpu")
                            .foregroundStyle(runtime.hasD3DMetal ? Color.accentColor : .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(runtime.name).fontWeight(.medium)
                                if runtimes.defaultRuntime?.id == runtime.id {
                                    Text("domyślne")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("\(runtime.version) · grafika: \(runtime.graphicsSummary) · \(sourceLabel(runtime.source))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(runtime.wineRoot.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Menu {
                            Button("Ustaw jako domyślne") { runtimes.setDefault(runtime) }
                            Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([runtime.wineRoot]) }
                            if runtime.source == .managed {
                                Divider()
                                Button("Usuń…", role: .destructive) { runtimeToDelete = runtime }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                ForEach(DownloadOffer.all) { offer in
                    OfferRow(offer: offer)
                }
            } header: {
                Text("Do pobrania")
            } footer: {
                Text("Buildy Wine pochodzą z projektów Gcenx na GitHubie (game-porting-toolkit, macOS_Wine_builds, DXVK-macOS).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Narzędzia") {
                StatusRow(
                    title: "Rosetta 2",
                    ok: Paths.rosettaInstalled,
                    detail: Paths.rosettaInstalled ? "Zainstalowana" : "Wymagana — w Terminalu: softwareupdate --install-rosetta --agree-to-license"
                )
                HStack {
                    StatusRow(title: "winetricks", ok: runtimes.winetricksInstalled,
                              detail: runtimes.winetricksInstalled ? "Pobrany" : "Pobierany automatycznie przy pierwszym użyciu")
                    if let progress = runtimes.progress["winetricks"] {
                        ProgressRow(progress: progress).frame(width: 160)
                    } else {
                        Button(runtimes.winetricksInstalled ? "Aktualizuj" : "Pobierz") {
                            Task { await runtimes.installWinetricks() }
                        }
                    }
                }
                HStack {
                    StatusRow(title: "cabextract", ok: Paths.cabextractPath != nil,
                              detail: Paths.cabextractPath ?? "Potrzebny dla winetricks — brew install cabextract")
                    if Paths.cabextractPath == nil, Paths.homebrewPath != nil {
                        Button("Zainstaluj w Terminalu") { TerminalHelper.run("brew install cabextract") }
                    }
                }
            }

            Section("Dane") {
                LabeledContent("Butelki, środowiska i logi") {
                    Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([Paths.appSupport]) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Środowiska Wine")
        .onAppear { runtimes.refresh() }
        .confirmationDialog(
            "Usunąć \(runtimeToDelete?.name ?? "")?",
            isPresented: Binding(get: { runtimeToDelete != nil }, set: { if !$0 { runtimeToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Przenieś do Kosza", role: .destructive) {
                if let runtime = runtimeToDelete { runtimes.delete(runtime) }
            }
        } message: {
            Text("Butelki korzystające z tego środowiska przestaną się uruchamiać, dopóki nie wybierzesz dla nich innego.")
        }
    }

    private func sourceLabel(_ source: WineRuntime.Source) -> String {
        switch source {
        case .managed: return "pobrane przez Crossway"
        case .whisky: return "z aplikacji Whisky"
        case .external: return "aplikacja w /Applications"
        }
    }
}

private struct OfferRow: View {
    let offer: DownloadOffer
    @EnvironmentObject private var runtimes: RuntimeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(offer.title).fontWeight(.medium)
                    if offer.recommended {
                        Text("zalecane")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }
                }
                Text(offer.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = runtimes.progress[offer.id] {
                    ProgressRow(progress: progress).padding(.top, 4)
                }
            }
            Spacer()
            if runtimes.progress[offer.id] == nil {
                Button(runtimes.isInstalled(offer) ? "Pobierz ponownie" : "Pobierz") {
                    Task { await runtimes.install(offer) }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatusRow: View {
    let title: String
    let ok: Bool
    let detail: String

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
        }
    }
}

enum TerminalHelper {
    /// Opens Terminal.app and types a command for the user to watch (and confirm if it asks).
    static func run(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}
