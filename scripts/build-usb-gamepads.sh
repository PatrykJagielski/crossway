#!/bin/bash
# Builds the libraries behind "Pady Xbox przez USB" into Sources/Crossway/Resources/UsbGamepads:
#   libSDL3.dylib       SDL 3.4.8 (x86_64, for Wine under Rosetta) with libusb support and
#                       scripts/sdl-usb-gamepads-macos.patch applied: wired Xbox pads are
#                       accepted, noticed when plugged in, and retried when another program
#                       held them
#   libusb-1.0.0.dylib  libusb 1.0.29 (x86_64), loaded by SDL from the same folder
#
# Why: macOS has no driver for wired third-party Xbox controllers (GIP protocol, e.g. Turtle
# Beach Recon), so they never show up as HID devices and Wine cannot see them. Wine's winebus
# reads controllers through SDL; this SDL can talk to them directly over USB instead.
# Needs: Xcode command line tools, cmake (brew install cmake), network.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/Sources/Crossway/Resources/UsbGamepads"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SDL_VERSION=3.4.8
SDL_SHA256=e9fff7467fb60f037e6708da18b25560649e4c63edc2a69bb871b960d9cbfbba
LIBUSB_VERSION=1.0.29
LIBUSB_SHA256=5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85
MIN_MACOS=11.0

fetch() { # url sha256 file
    curl -fsSL "$1" -o "$WORK/$3"
    echo "$2  $WORK/$3" | shasum -a 256 -c - >/dev/null || { echo "Zła suma kontrolna: $3" >&2; exit 1; }
}

echo "→ Pobieranie źródeł…"
fetch "https://github.com/libusb/libusb/releases/download/v$LIBUSB_VERSION/libusb-$LIBUSB_VERSION.tar.bz2" "$LIBUSB_SHA256" libusb.tar.bz2
fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL3-$SDL_VERSION.tar.gz" "$SDL_SHA256" sdl.tar.gz
tar -xjf "$WORK/libusb.tar.bz2" -C "$WORK"
tar -xzf "$WORK/sdl.tar.gz" -C "$WORK"

echo "→ libusb $LIBUSB_VERSION (x86_64)…"
(cd "$WORK/libusb-$LIBUSB_VERSION" &&
    CC="clang -arch x86_64" CFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS" LDFLAGS="-mmacosx-version-min=$MIN_MACOS" \
        ./configure --host=x86_64-apple-darwin --prefix="$WORK/prefix" --disable-static >/dev/null &&
    make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null)
# SDL finds it next to itself.
install_name_tool -id @loader_path/libusb-1.0.0.dylib "$WORK/prefix/lib/libusb-1.0.0.dylib" 2>/dev/null

echo "→ SDL $SDL_VERSION z libusb (x86_64)…"
patch -d "$WORK/SDL3-$SDL_VERSION" -p1 < "$ROOT/scripts/sdl-usb-gamepads-macos.patch" >/dev/null
PKG_CONFIG_PATH="$WORK/prefix/lib/pkgconfig" PKG_CONFIG_LIBDIR="$WORK/prefix/lib/pkgconfig" \
cmake -S "$WORK/SDL3-$SDL_VERSION" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_MACOS \
    -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DCMAKE_SYSTEM_IGNORE_PREFIX_PATH=/opt/homebrew \
    -DSDL_HIDAPI_LIBUSB=ON -DSDL_HIDAPI_LIBUSB_SHARED=OFF \
    -DLibUSB_LIBRARY="$WORK/prefix/lib/libusb-1.0.0.dylib" -DLibUSB_INCLUDE_PATH="$WORK/prefix/include/libusb-1.0" \
    -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF >/dev/null
cmake --build "$WORK/build" -j"$(sysctl -n hw.ncpu)" >/dev/null

mkdir -p "$OUT"
cp "$WORK/build/libSDL3.0.dylib" "$OUT/libSDL3.dylib"
cp "$WORK/prefix/lib/libusb-1.0.0.dylib" "$OUT/libusb-1.0.0.dylib"
codesign --force --sign - "$OUT/libSDL3.dylib" "$OUT/libusb-1.0.0.dylib" 2>/dev/null
echo "✓ Gotowe: $OUT"
