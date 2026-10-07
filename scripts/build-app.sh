#!/bin/bash
# Builds Crossway.app into ./build. Usage: scripts/build-app.sh [--install]
#   --install  also copies the app to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Crossway.app"
VERSION="1.0.0"

echo "→ Kompilacja (release, arm64)…"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Crossway"

echo "→ Tworzenie paczki $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Crossway"

if [ ! -f build/AppIcon.icns ]; then
    echo "→ Generowanie ikony…"
    ICONSET="build/AppIcon.iconset"
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    swift scripts/make-icon.swift build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/Crossway/Resources/steamwebhelper-wrapper.exe "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Crossway</string>
    <key>CFBundleDisplayName</key><string>Crossway</string>
    <key>CFBundleIdentifier</key><string>pl.crossway.app</string>
    <key>CFBundleExecutable</key><string>Crossway</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>pl</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Crossway otwiera Terminal, aby zainstalować narzędzia (np. cabextract).</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Program Windows</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>exe</string><string>msi</string><string>bat</string><string>lnk</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "→ Podpisywanie (ad-hoc)…"
codesign --force --deep --sign - "$APP"

if [ "${1:-}" = "--install" ]; then
    echo "→ Instalacja w /Applications…"
    rm -rf /Applications/Crossway.app
    cp -R "$APP" /Applications/
    echo "✓ Zainstalowano: /Applications/Crossway.app"
else
    echo "✓ Gotowe: $APP"
fi
