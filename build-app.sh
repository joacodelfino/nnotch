#!/bin/bash
# Compila nnotch.app sin requerir Xcode completo.
# Uso: ./build-app.sh [--run]
set -euo pipefail

cd "$(dirname "$0")"

# En macOS 27 CommandLineTools (sin Xcode completo) falta libSwiftUIMacros.dylib en el SDK 27.x;
# si detectamos ese caso y está disponible MacOSX26.5.sdk, compilamos contra ese SDK.
SDK_PATH="$(xcrun --show-sdk-path)"
CLT_PLUGINS="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins"
FALLBACK_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ "$SDK_PATH" == /Library/Developer/CommandLineTools/* ]] \
   && [[ ! -f "$CLT_PLUGINS/libSwiftUIMacros.dylib" ]] \
   && [[ -d "$FALLBACK_SDK" ]]; then
    SDK_PATH="$FALLBACK_SDK"
fi

MODULE_CACHE="${TMPDIR:-/tmp}/nnotch-module-cache"
mkdir -p .build/release "$MODULE_CACHE"

APP="build/nnotch.app"
BIN=".build/release/NNotch"

echo "▸ Compilando nnotch (release)…"
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find Sources/NNotch -name '*.swift' | sort)

swiftc \
    -O -whole-module-optimization \
    -parse-as-library \
    -target arm64-apple-macosx14.0 \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    "${SOURCES[@]}" \
    -o "$BIN"

echo "▸ Armando bundle: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/nnotch"
cp AppBundle/Info.plist "$APP/Contents/Info.plist"
cp AppBundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Firmando app localmente (ad-hoc)…"
codesign --force --sign - "$APP"

echo "✓ Listo: $APP"
if [[ "${1:-}" == "--run" ]]; then
    echo "▸ Reiniciando nnotch…"
    killall nnotch 2>/dev/null || killall n-notch 2>/dev/null || killall JNotch 2>/dev/null || true
    sleep 0.3
    open "$APP"
fi
