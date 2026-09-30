#!/usr/bin/env bash
# Builds Zone.app from the Swift package: release binary, Info.plist, icon, ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Zone"
APP="Zone.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Zone"
cp Info.plist "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --render-icon Resources/Logo.png "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: needed for notifications to be delivered.
codesign --force --sign - "$APP"
echo "Built $APP"
