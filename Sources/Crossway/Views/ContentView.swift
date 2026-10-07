import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var runtimes: RuntimeManager
    @EnvironmentObject private var runner: WineRunner

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detail
        }
        .sheet(isPresented: $state.showNewBottle) {
            NewBottleSheet { id in state.selection = id }
        }
        .sheet(isPresented: $state.showRuntimes) {
            NavigationStack {
                RuntimesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Gotowe") { state.showRuntimes = false }
                        }
                    }
            }
            .frame(width: 720, height: 600)
        }
        .sheet(item: Binding(
            get: { state.pendingOpenFile.map(IdentifiedURL.init) },
            set: { state.pendingOpenFile = $0?.url }
        )) { item in
            OpenFileSheet(file: item.url)
        }
        .alert("Błąd", isPresented: Binding(
            get: { bottles.lastError != nil || runtimes.lastError != nil },
            set: { if !$0 { bottles.lastError = nil; runtimes.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bottles.lastError ?? runtimes.lastError ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $state.selection) {
            Section("Butelki") {
                ForEach(bottles.bottles) { bottle in
                    BottleRow(bottle: bottle)
                        .tag(bottle.id)
                        .contextMenu {
                            Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([bottle.url]) }
                            Button("Duplikuj") { Task { await bottles.duplicate(bottle) } }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if bottles.bottles.isEmpty {
                ContentUnavailableView {
                    Label("Brak butelek", systemImage: "wineglass")
                } description: {
                    Text("Butelka to osobny „komputer z Windows” dla Twoich gier.")
                } actions: {
                    Button("Nowa butelka") { state.showNewBottle = true }
                        .disabled(runtimes.runtimes.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button {
                        state.showRuntimes = true
                    } label: {
                        Label("Środowiska Wine", systemImage: "shippingbox")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    if !runner.running.isEmpty {
                        Label("\(runner.running.count)", systemImage: "play.circle.fill")
                            .foregroundStyle(.green)
                            .help("Uruchomione procesy")
                    }
                }
                .padding(10)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    state.showNewBottle = true
                } label: {
                    Label("Nowa butelka", systemImage: "plus")
                }
                .disabled(runtimes.runtimes.isEmpty)
                .help("Nowa butelka (⌘N)")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if runtimes.runtimes.isEmpty {
            WelcomeView()
        } else if let bottle = bottles.bottle(id: state.selection) {
            BottleDetailView(bottleID: bottle.id)
                .id(bottle.id)
        } else {
            ContentUnavailableView {
                Label("Wybierz butelkę", systemImage: "wineglass")
            } description: {
                Text("Wybierz butelkę z listy albo utwórz nową, aby zainstalować grę.")
            } actions: {
                Button("Nowa butelka") { state.showNewBottle = true }
            }
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct BottleRow: View {
    let bottle: Bottle
    @EnvironmentObject private var runner: WineRunner
    @EnvironmentObject private var bottles: BottleManager
    @EnvironmentObject private var runtimes: RuntimeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wineglass.fill")
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.name)
                    .lineLimit(1)
                Text(runtimes.runtime(id: bottle.runtimeID)?.name ?? "Brak środowiska")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if bottles.busy[bottle.id] != nil {
                ProgressView().controlSize(.small)
            } else if !runner.running(in: bottle).isEmpty {
                Circle().fill(.green).frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
    }
}
