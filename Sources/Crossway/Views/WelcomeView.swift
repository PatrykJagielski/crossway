import SwiftUI

/// First-run screen shown until at least one Wine runtime is available.
struct WelcomeView: View {
    @EnvironmentObject private var runtimes: RuntimeManager

    private var gptk: DownloadOffer { DownloadOffer.all.first { $0.recommended }! }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "wineglass.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                VStack(spacing: 8) {
                    Text("Witaj w Crossway")
                        .font(.largeTitle.bold())
                    Text("Graj w gry z Windows na swoim Macu z Apple Silicon.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Krok 1: pobierz środowisko Wine", systemImage: "1.circle.fill")
                            .font(.headline)
                        Text("Crossway używa Wine z kodu CrossOver z D3DMetal od Apple (DirectX 11/12 → Metal) oraz DXMT i DXVK. Pobranie to ok. 250 MB, po rozpakowaniu ~1,5 GB.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let progress = runtimes.progress[gptk.id] {
                            ProgressRow(progress: progress)
                        } else {
                            Button {
                                Task { await runtimes.install(gptk) }
                            } label: {
                                Label("Pobierz środowisko Wine", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        Text("D3DMetal jest objęty licencją Apple — dozwolony do oceny i uruchamiania gier na własnym Macu.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Potem", systemImage: "2.circle.fill").font(.headline)
                        Text("• Utwórz butelkę (⌘N) — osobny prefiks Windows dla gier.")
                        Text("• Zainstaluj Steam, Epic, GOG lub Battle.net z katalogu albo dowolny instalator .exe.")
                        Text("• Uruchamiaj gry jednym kliknięciem lub dodaj je do Launchpada.")
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                if !Paths.rosettaInstalled {
                    GroupBox {
                        Label("Rosetta 2 nie jest zainstalowana. Wine wymaga Rosetty. Uruchom w Terminalu: softwareupdate --install-rosetta --agree-to-license", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: 560)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ProgressRow: View {
    let progress: TaskProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(progress.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
