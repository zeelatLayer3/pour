#!/bin/zsh
# Builds Pour.app into ./build and, with --install, copies it to /Applications and launches it.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/Pour.app"
VERSION="1.0.1"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Pour"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pour"

ICONSET="$ROOT/build/Pour.iconset"
rm -rf "$ICONSET"
"$BIN" --iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Pour.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Pour</string>
	<key>CFBundleDisplayName</key><string>Pour</string>
	<key>CFBundleIdentifier</key><string>xyz.layer3.pour</string>
	<key>CFBundleExecutable</key><string>Pour</string>
	<key>CFBundleIconFile</key><string>Pour</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>2</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>NSHumanReadableCopyright</key><string>Keeps your Mac awake, one cup at a time.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Pour 2>/dev/null || true
  rm -rf "/Applications/Pour.app"
  cp -R "$APP" "/Applications/Pour.app"
  open "/Applications/Pour.app"
  echo "Installed to /Applications/Pour.app"
fi
