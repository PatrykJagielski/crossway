import SwiftUI

struct InstallView: View {
    let bottle: Bottle

    @EnvironmentObject private var installs: InstallManager
    @State private var verbs = ""
    @State private var expandedJob: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                let jobs = installs.jobs(for: bottle)
                if !jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Instalacje").font(.headline)
                            Spacer()
                            if jobs.contains(where: \.finished) {
                                Button("Wyczyść zakończone") { installs.clearFinished() }.buttonStyle(.borderless)
                            }
                        }
                        ForEach(jobs) { job in
                            JobRow(job: job, expanded: expandedJob == job.id) {
                                expandedJob = expandedJob == job.id ? nil : job.id
                            }
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Własny instalator").font(.headline)
                        Text("Plik .exe lub .msi, np. instalator gry z GOG lub płyty.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        pickInstaller()
                    } label: {
                        Label("Wybierz plik…", systemImage: "folder")
                    }
                    .controlSize(.large)
                }
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                ForEach(CatalogItem.Category.allCases) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.rawValue).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                            ForEach(CatalogItem.all.filter { $0.category == category }) { item in
                                CatalogCard(item: item) { installs.install(item, in: bottle) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("winetricks").font(.headline)
                    Text("Zainstaluj dowolne komponenty winetricks (np. vcrun2019 dxvk physx). Lista: winetricks list-all.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("pakiety oddzielone spacją", text: $verbs)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(runVerbs)
                        Button("Instaluj", action: runVerbs)
                            .disabled(verbs.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if Paths.cabextractPath == nil {
                        Label("Brakuje cabextract — wymagany przez winetricks. Zainstaluj: brew install cabextract", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(20)
        }
    }

    private func runVerbs() {
        let list = verbs.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !list.isEmpty else { return }
        installs.runWinetricks(verbs: list, in: bottle)
        verbs = ""
    }

    private func pickInstaller() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = WindowsFileTypes.all
        panel.allowsOtherFileTypes = true
        panel.message = "Wybierz instalator Windows (.exe / .msi)"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installs.installFile(url, in: bottle)
    }
}

private struct CatalogCard: View {
    let item: CatalogItem
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(item.category == .stores ? Color.accentColor : Color.gray, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).fontWeight(.semibold)
                Text(item.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let tips = item.tips {
                    Text(tips).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button("Instaluj", action: install)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

private struct JobRow: View {
    let job: InstallManager.Job
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: job.failed ? "xmark.octagon.fill" : job.finished ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(job.failed ? .red : job.finished ? .green : .accentColor)
                Text(job.title).fontWeight(.medium)
                Spacer()
                if !job.output.isEmpty {
                    Button(expanded ? "Ukryj szczegóły" : "Szczegóły", action: toggle).buttonStyle(.borderless)
                }
            }
            if !job.finished {
                if let fraction = job.fraction { ProgressView(value: fraction) } else { ProgressView().progressViewStyle(.linear) }
            }
            Text(job.status).font(.caption).foregroundStyle(job.failed ? .red : .secondary).textSelection(.enabled)
            if expanded {
                ScrollView {
                    Text(job.output)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(8)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
