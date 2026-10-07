import SwiftUI
import UniformTypeIdentifiers

struct ProgramsView: View {
    let bottle: Bottle

    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var runner: WineRunner
    @State private var shortcuts: [DiscoveredProgram] = []
    @State private var executables: [DiscoveredProgram] = []
    @State private var showAllExecutables = false
    @State private var search = ""
    @State private var editing: PinnedProgram?
    @State private var error: String?
    @State private var info: String?
    @State private var dropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !bottle.programs.isEmpty {
                    section("Przypięte") {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(bottle.programs) { program in
                                ProgramCard(name: program.name, subtitle: program.arguments.isEmpty ? nil : program.arguments,
                                            symbol: "star.fill", pinned: true,
                                            missing: !FileManager.default.fileExists(atPath: program.path)) {
                                    launch(program)
                                } menu: {
                                    Button("Uruchom") { launch(program) }
                                    Button("Edytuj nazwę i argumenty…") { editing = program }
                                    Button("Dodaj do Launchpada") { makeShortcut(program) }
                                    Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([program.url]) }
                                    Divider()
                                    Button("Odepnij") { bottles.unpin(path: program.path, in: bottle) }
                                }
                            }
                        }
                    }
                }

                section("Menu Start") {
                    if filteredShortcuts.isEmpty {
                        emptyHint
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filteredShortcuts) { program in
                                discoveredCard(program, symbol: "app.badge.fill")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    DisclosureGroup(isExpanded: $showAllExecutables) {
                        if filteredExecutables.isEmpty {
                            Text("Nie znaleziono plików .exe w Program Files.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredExecutables) { program in
                                    ExecutableRow(program: program) { launch(program) } pin: { pin(program) }
                                    Divider()
                                }
                            }
                            .padding(.top, 6)
                        }
                    } label: {
                        Text("Wszystkie pliki .exe (\(filteredExecutables.count))")
                            .font(.headline)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Szukaj programów")
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.06))
                    .overlay(Label("Upuść, aby uruchomić w „\(bottle.name)”", systemImage: "play.circle").font(.title2))
                    .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .task(id: runner.running(in: bottle).count) { await rescan() }
        .sheet(item: $editing) { program in
            ProgramEditSheet(program: program) { bottles.updateProgram($0, in: bottle) }
        }
        .alert("Błąd", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert("Gotowe", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(info ?? "") }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Brak zainstalowanych programów.")
            Text("Przejdź do zakładki „Instaluj”, aby dodać Steam lub inny launcher, albo przeciągnij tutaj plik .exe.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var filteredShortcuts: [DiscoveredProgram] {
        let pinnedPaths = Set(bottle.programs.map(\.path))
        return shortcuts.filter { !pinnedPaths.contains($0.url.path) && matches($0.name) }
    }

    private var filteredExecutables: [DiscoveredProgram] {
        executables.filter { matches($0.name) || matches($0.location) }
    }

    private func matches(_ text: String) -> Bool {
        search.isEmpty || text.localizedCaseInsensitiveContains(search)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func discoveredCard(_ program: DiscoveredProgram, symbol: String) -> some View {
        ProgramCard(name: program.name, subtitle: program.location, symbol: symbol, pinned: false, missing: false) {
            launch(program)
        } menu: {
            Button("Uruchom") { launch(program) }
            Button("Przypnij") { pin(program) }
            Button("Dodaj do Launchpada") { makeShortcut(PinnedProgram(name: program.name, path: program.url.path)) }
            Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([program.url]) }
        }
    }

    private func rescan() async {
        let snapshot = bottle
        let (found, exes) = await Task.detached(priority: .utility) {
            (ProgramScanner.shortcuts(in: snapshot), ProgramScanner.executables(in: snapshot))
        }.value
        shortcuts = found
        executables = exes
    }

    private func pin(_ program: DiscoveredProgram) {
        bottles.pin(PinnedProgram(name: program.name, path: program.url.path), in: bottle)
    }

    private func launch(_ program: DiscoveredProgram) {
        run { try runner.launch(file: program.url, name: program.name, in: bottle, runtime: $0) }
    }

    private func launch(_ program: PinnedProgram) {
        run { try runner.launch(file: program.url, arguments: program.arguments, name: program.name, in: bottle, runtime: $0) }
    }

    private func run(_ body: (WineRuntime) throws -> Void) {
        do {
            try body(bottles.runtime(for: bottle))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func makeShortcut(_ program: PinnedProgram) {
        do {
            let app = try ShortcutMaker.createShortcut(name: program.name, program: program, bottle: bottle)
            info = "Utworzono „\(app.deletingPathExtension().lastPathComponent)” w ~/Applications/Crossway. Znajdziesz go w Launchpadzie i Spotlight; możesz też przeciągnąć go do Docka."
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                run { try runner.launch(file: url, in: bottle, runtime: $0) }
            }
        }
        return true
    }
}

private struct ProgramCard<MenuContent: View>: View {
    let name: String
    let subtitle: String?
    let symbol: String
    let pinned: Bool
    let missing: Bool
    let action: () -> Void
    @ViewBuilder let menu: () -> MenuContent
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: pinned ? [.orange, .pink] : [.blue, .indigo],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 58, height: 58)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if hovering {
                        RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.35)).frame(width: 58, height: 58)
                        Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                    }
                }
                VStack(spacing: 2) {
                    Text(name)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if missing {
                        Text("Plik nie istnieje").font(.caption2).foregroundStyle(.orange)
                    } else if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { menu() }
        .help(name)
    }
}

private struct ExecutableRow: View {
    let program: DiscoveredProgram
    let launch: () -> Void
    let pin: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(program.name)
                Text(program.location).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Przypnij", action: pin).buttonStyle(.borderless)
            Button("Uruchom", action: launch)
        }
        .padding(.vertical, 6)
    }
}

struct ProgramEditSheet: View {
    @State var program: PinnedProgram
    let onSave: (PinnedProgram) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Nazwa", text: $program.name)
                TextField("Argumenty", text: $program.arguments, prompt: Text("np. -dx11 -windowed"))
                LabeledContent("Plik") {
                    Text(program.path).font(.caption.monospaced()).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Anuluj") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Zapisz") { onSave(program); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480, height: 260)
    }
}
