import SwiftUI

struct LogsView: View {
    let bottle: Bottle

    @EnvironmentObject private var runner: WineRunner
    @State private var files: [URL] = []
    @State private var selected: URL?
    @State private var content = ""

    var body: some View {
        HSplitView {
            List(files, id: \.self, selection: $selected) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(of: file)).lineLimit(1)
                    Text(date(of: file)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            .overlay {
                if files.isEmpty {
                    ContentUnavailableView("Brak logów", systemImage: "doc.text", description: Text("Logi pojawią się po uruchomieniu programu."))
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Text(selected.map(title(of:)) ?? "").font(.headline).lineLimit(1)
                    Spacer()
                    Button {
                        Task { await load() }
                    } label: { Label("Odśwież", systemImage: "arrow.clockwise") }
                    Button {
                        if let selected { NSWorkspace.shared.activateFileViewerSelecting([selected]) }
                    } label: { Label("Pokaż w Finderze", systemImage: "folder") }
                    .disabled(selected == nil)
                    Button(role: .destructive) {
                        deleteAll()
                    } label: { Label("Usuń wszystkie", systemImage: "trash") }
                    .disabled(files.isEmpty)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(10)
                Divider()
                ScrollView {
                    Text(content)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
            .frame(minWidth: 380)
        }
        .task { refreshList() }
        .onChange(of: runner.running.count) { refreshList() }
        .task(id: selected) { await load() }
    }

    private func refreshList() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: bottle.logsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        files = urls.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        if selected == nil || !files.contains(selected!) { selected = files.first }
    }

    private func load() async {
        guard let selected else { content = ""; return }
        content = await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: selected) else { return "" }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            let limit: UInt64 = 300_000
            try? handle.seek(toOffset: size > limit ? size - limit : 0)
            let data = (try? handle.readToEnd()) ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            return size > limit ? "… (pokazano ostatnie 300 KB)\n" + text : text
        }.value
    }

    private func deleteAll() {
        for file in files { try? FileManager.default.removeItem(at: file) }
        selected = nil
        refreshList()
    }

    /// Log names look like 2026-10-07_15-30-00_Steam.log
    private func title(of url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "_", maxSplits: 2)
        return parts.count == 3 ? String(parts[2]) : name
    }

    private func date(of url: URL) -> String {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_", maxSplits: 2)
        guard parts.count == 3 else { return "" }
        return parts[0] + " " + parts[1].replacingOccurrences(of: "-", with: ":")
    }
}
