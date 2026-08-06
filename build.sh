#!/bin/bash
set -euo pipefail

SDK_VERSION=$(xcrun --show-sdk-version)
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
    echo "error: building Limón requires the macOS 26 SDK or newer (found $SDK_VERSION)" >&2
    echo "install Xcode 26+ and select it with: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

APP="Limón.app"
BIN="Limon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/Info.plist"

[ -f AppIcon.icns ] || swift make-icon.swift
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
echo "Run it:      open '$APP'"
echo "Install it:  cp -r '$APP' /Applications/"
