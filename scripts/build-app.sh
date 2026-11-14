#!/usr/bin/env bash
# Build "dist/AI Usage Bar.app" (universal) and dist/AI-Usage-Bar.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(node -p "require('./package.json').version")"
APP="$ROOT/dist/AI Usage Bar.app"
ZIP="$ROOT/dist/AI-Usage-Bar.zip"

echo "Building AI Usage Bar $VERSION"
(cd app && swift build -c release --arch arm64 --arch x86_64)
BIN="$(cd app && swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AIUsageBar"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AIUsageBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.verycuteapps.ai-usage-bar</string>
  <key>CFBundleName</key><string>AI Usage Bar</string>
  <key>CFBundleDisplayName</key><string>AI Usage Bar</string>
  <key>CFBundleExecutable</key><string>AIUsageBar</string>
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
echo "Archs: $(lipo -archs "$APP/Contents/MacOS/AIUsageBar")"
