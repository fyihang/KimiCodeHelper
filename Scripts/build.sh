#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Kimi Web.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/app-template/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/app-template/icon.icns" ]; then
  cp "$ROOT/app-template/icon.icns" "$APP/Contents/Resources/icon.icns"
fi
swiftc -parse-as-library -O -o "$APP/Contents/MacOS/kimi-web-launcher" "$ROOT/Sources/main.swift"
echo "built: $APP"
