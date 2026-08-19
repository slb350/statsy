#!/bin/bash
# Assembles Statsy.app around the SwiftPM binary.
#
# SwiftPM cannot emit an app bundle, and the panel needs one to carry
# LSUIElement (no Dock icon) and to be launchable at login.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Statsy"
APP="$ROOT/.build/Statsy.app"

swift build -c "$CONFIG"

# Never cp -R over an existing bundle: a running binary is locked and the copy
# silently leaves the old executable in place.
[ -d "$APP" ] && { command -v trash >/dev/null && trash "$APP" || rm -rf "$APP"; }

mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Statsy"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Statsy</string>
    <key>CFBundleDisplayName</key>     <string>Statsy</string>
    <key>CFBundleIdentifier</key>      <string>dev.steve.statsy</string>
    <key>CFBundleExecutable</key>      <string>Statsy</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- A panel, not an app: no Dock icon, no menu bar. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || echo "note: ad-hoc signing unavailable"
echo "built $APP"
echo "run:  open $APP"
