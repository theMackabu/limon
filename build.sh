#!/bin/bash
set -euo pipefail

SDK_VERSION=$(xcrun --show-sdk-version)
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
    echo "error: building Limón requires the macOS 26 SDK or newer (found $SDK_VERSION)" >&2
    echo "install Xcode 26+ and select it with: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

BUILD="Build"
APP="$BUILD/Limón.app"
BIN="Limon"
DMG="$BUILD/Limon.dmg"
VOLUME="Limon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/Info.plist"

[ -f AppIcon.icns ] || swift scripts/make-icon.swift
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc \
    -O \
    -parse-as-library \
    -target "$(uname -m)-apple-macosx26.0" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$APP/Contents/MacOS/$BIN" \
    Sources/*.swift

codesign --force --deep --sign - "$APP"

echo "Built $APP"

BACKGROUND="$BUILD/dmg-background.png"
swift scripts/make-dmg-background.swift "$BACKGROUND" >/dev/null

STAGE="$BUILD/dmg-stage"
LAYOUT="scripts/dmg-window-layout"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
cp "$BACKGROUND" "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"
[ -f "$LAYOUT" ] && cp "$LAYOUT" "$STAGE/.DS_Store"

RW_DMG="$BUILD/rw.dmg"
rm -f "$RW_DMG" "$DMG"
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -ov -quiet "$RW_DMG"

MOUNT_DIR="/Volumes/$VOLUME"
hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
hdiutil attach "$RW_DMG" -nobrowse -quiet

STYLED=1
osascript <<APPLESCRIPT >/dev/null 2>&1 || STYLED=0
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 840, 588}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 112
        set background picture of options to file ".background:background.png"
        set position of item "Limón.app" of container window to {170, 205}
        set position of item "Applications" of container window to {470, 205}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

if [ "$STYLED" = "1" ] && [ -f "$MOUNT_DIR/.DS_Store" ]; then
    mkdir -p "$(dirname "$LAYOUT")"
    cp "$MOUNT_DIR/.DS_Store" "$LAYOUT"
else
    echo "note: Finder styling unavailable; used the saved window layout"
fi

sync
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -ov -quiet
rm -f "$RW_DMG"
rm -rf "$STAGE"

echo "Built $DMG"
echo "Run it:      open '$APP'"
echo "Install it:  open '$DMG'"
