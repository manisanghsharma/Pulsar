#!/bin/bash
# Builds Pulsar.app and Pulsar.dmg into ./build
set -euo pipefail
cd "$(dirname "$0")"

NAME=Pulsar
VERSION=1.0.0
OUT=build
APP="$OUT/$NAME.app"
rm -rf "$APP" "$OUT/$NAME.dmg" "$OUT/dmg" "$OUT/tmp.dmg"
mkdir -p "$OUT"

echo "▸ Compiling"
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0
BIN="$OUT/$NAME-universal"
lipo -create -output "$BIN" \
  "$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/$NAME" \
  "$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/$NAME"

echo "▸ Rendering icon"
swift scripts/make_assets.swift "$OUT"
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$OUT/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"

echo "▸ Bundling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp "$OUT/AppIcon.icns" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>app.pulsar.autoclicker</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Pulsar</string>
</dict></plist>
PLIST
# Stable requirement (bundle ID, not build hash) so the Accessibility grant survives rebuilds.
codesign --force --deep --sign - -r='designated => identifier "app.pulsar.autoclicker"' "$APP"

echo "▸ Packaging DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$OUT/dmg_bg.png" "$STAGE/.background/bg.png"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW "$OUT/tmp.dmg"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$OUT/tmp.dmg" | awk '/Apple_HFS/ {print $1}')
# Finder layout is cosmetic; skip quietly if Finder automation is not allowed.
osascript <<OSA || echo "  (Finder layout skipped)"
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:bg.png"
    set position of item "$NAME.app" of container window to {170, 190}
    set position of item "Applications" of container window to {490, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
hdiutil detach -quiet "$DEV"
hdiutil convert -quiet "$OUT/tmp.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT/$NAME.dmg"
rm -rf "$OUT/tmp.dmg" "$STAGE" "$ICONSET" "$BIN"
echo "✓ $OUT/$NAME.dmg"
