#!/bin/bash
# Assemble Marginalia.app from SwiftPM products. Usage: Scripts/bundle.sh [debug|release]
set -euo pipefail
CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/$CONFIG"
APP="$ROOT/_build/Marginalia.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Marginalia" "$APP/Contents/MacOS/Marginalia"
cp "$BIN/md" "$APP/Contents/MacOS/md"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/Fonts" "$APP/Contents/Resources/Fonts"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# swift-markdown ships a resource bundle in some versions; copy any next to the binary.
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/MacOS/"; done
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --sign - --identifier com.sjbp.marginalia "$APP" >/dev/null 2>&1
echo "bundled $APP ($CONFIG)"
