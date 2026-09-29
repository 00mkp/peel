#!/usr/bin/env bash
# Builds Peel.app from the PeelApp target and installs it to $APP_DIR (default ~/Applications).
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/Applications}"
case "$APP_DIR" in /*) ;; *) APP_DIR="$PWD/$APP_DIR" ;; esac   # relative to where you ran it
cd "$(dirname "$0")/.."
VERSION="0.2.0"

echo "Building Peel.app (release)…"
swift build -c release --product PeelApp
BIN="$(swift build -c release --show-bin-path)/PeelApp"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Peel.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Peel"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Peel</string>
  <key>CFBundleExecutable</key><string>Peel</string>
  <key>CFBundleIdentifier</key><string>dev.peel.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Peel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Any file</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.item</string><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
mkdir -p "$APP_DIR"
rm -rf "$APP_DIR/Peel.app"
mv "$APP" "$APP_DIR/Peel.app"
echo "Installed $APP_DIR/Peel.app"
