#!/bin/bash
# Assembles Statsy.app and Statsy Menu.app around the SwiftPM binaries.
#
# SwiftPM cannot emit an app bundle, and both need one: the panel to carry
# LSUIElement (no Dock icon) and to be launchable at login, the controller to
# be a findable app that Launch Services can start.
#
# The two bundles must stay siblings — the controller looks for the panel
# beside itself before it looks anywhere else.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

swift build -c "$CONFIG"

# bundle <executable> <app name> <bundle identifier>
bundle() {
    local executable="$1" app_name="$2" identifier="$3"
    local app="$ROOT/.build/$app_name.app"

    # Never cp -R over an existing bundle: a running binary is locked and the
    # copy silently leaves the old executable in place.
    [ -d "$app" ] && { command -v trash >/dev/null && trash "$app" || rm -rf "$app"; }

    mkdir -p "$app/Contents/MacOS"
    cp "$BIN_DIR/$executable" "$app/Contents/MacOS/$executable"

    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$app_name</string>
    <key>CFBundleDisplayName</key>     <string>$app_name</string>
    <key>CFBundleIdentifier</key>      <string>$identifier</string>
    <key>CFBundleExecutable</key>      <string>$executable</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- Neither is an app you switch to: no Dock icon, no menu bar. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

    codesign --force --sign - "$app" 2>/dev/null || echo "note: ad-hoc signing unavailable"
    echo "built $app"
}

bundle Statsy     "Statsy"      dev.steve.statsy
bundle StatsyMenu "Statsy Menu" dev.steve.statsy.menu

echo "run:  open '$ROOT/.build/Statsy Menu.app'"
