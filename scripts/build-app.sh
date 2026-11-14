#!/usr/bin/env bash
# Build "dist/AI Spend Bar.app" (universal) and dist/AI-Spend-Bar.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
NPM_VERSION="$(node -p "require('./package.json').version")"
# Versions are yyyyMMdd.N; npm requires three parts, so package.json carries yyyyMMdd.N.0.
VERSION="${NPM_VERSION%.0}"
APP="$ROOT/dist/AI Spend Bar.app"
ZIP="$ROOT/dist/AI-Spend-Bar.zip"

echo "Building AI Spend Bar $VERSION"
(cd app && swift build -c release --arch arm64 --arch x86_64)
BIN="$(cd app && swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AISpendBar"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AISpendBar"
# App icon ({$} on mint). Regenerate with: swift design/icon/render.swift
mkdir -p "$APP/Contents/Resources"
cp app/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.verycuteapps.ai-usage-bar</string>
  <key>CFBundleName</key><string>AI Spend Bar</string>
  <key>CFBundleDisplayName</key><string>AI Spend Bar</string>
  <key>CFBundleExecutable</key><string>AISpendBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © $(date +%Y) Very Cute Apps. MIT License.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "App:   $APP"
echo "Zip:   $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "Archs: $(lipo -archs "$APP/Contents/MacOS/AISpendBar")"
