# Crossway

Natywna aplikacja macOS (SwiftUI) do uruchamiania gier i programów z Windows na Macach z Apple Silicon — własna wersja CrossOvera, zbudowana na Wine + D3DMetal z Game Porting Toolkit od Apple.

## Budowanie

Wymagania: macOS 14+, Xcode 16+ (Swift 6), Rosetta 2.

```bash
scripts/build-app.sh            # → build/Crossway.app
scripts/build-app.sh --install  # dodatkowo kopiuje do /Applications
```

## Jak to działa

| Element | Odpowiednik w CrossOver | Implementacja |
|---|---|---|
| **Środowisko Wine** | silnik CrossOver | Pobierane z GitHuba (Gcenx): *Game Porting Toolkit 3* (Wine 7.7 + D3DMetal 3.0), *Wine Staging/Devel 11.x*. Wykrywa też WhiskyWine i aplikacje Wine w `/Applications`. |
| **Butelka** | bottle | Osobny `WINEPREFIX` w `~/Library/Application Support/Crossway/Bottles/<uuid>` + `crossway-bottle.json`. |
| **Grafika** | D3DMetal / DXVK | D3DMetal (DX11/12 → Metal, DXR, DLSS→MetalFX) lub DXVK-macOS (DX9–11 → Vulkan → MoltenVK; tylko środowiska z Vulkanem). |
| **CrossTie** | instalatory | Katalog: Steam, Epic, GOG Galaxy, Battle.net, EA app, Ubisoft Connect, Rockstar + pakiety winetricks. |
| **Skróty** | ikony w Launchpadzie | `~/Applications/Crossway/<Gra>.app` uruchamiające `Crossway --launch <butelka> <exe>`. |

Inne funkcje: ustawienia butelki (wersja Windows, ESync/MSync, AVX dla Rosetty, Retina, ⌘ jako Ctrl, Metal HUD, zmienne środowiskowe, nadpisania DLL), narzędzia Wine (winecfg, regedit, taskmgr, cmd…), logi każdego uruchomienia, duplikowanie butelek (klony APFS), otwieranie `.exe` z Findera.

## Wiersz poleceń

```bash
Crossway.app/Contents/MacOS/Crossway --cli runtimes
Crossway.app/Contents/MacOS/Crossway --cli download gptk        # gptk | wine-staging | wine-devel | dxvk
Crossway.app/Contents/MacOS/Crossway --cli create "Steam"
Crossway.app/Contents/MacOS/Crossway --cli run "Steam" ~/Downloads/SteamSetup.exe
Crossway.app/Contents/MacOS/Crossway --cli run "Steam" cmd /c ver
```

## Ograniczenia

- Gry z anty-cheatem na poziomie jądra (Valorant, Fortnite, wiele tytułów EA/Battlefield, CoD multiplayer) nie działają pod żadnym Wine.
- GPTK nie ma Vulkana — DXVK wymaga środowiska Wine Staging/Devel.
- `winetricks` potrzebuje `cabextract` (`brew install cabextract`).
- D3DMetal objęty licencją Apple (dozwolony do uruchamiania gier na własnym Macu).
