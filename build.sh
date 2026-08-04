#!/bin/bash
set -euo pipefail

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
    -target "$(uname -m)-apple-macosx14.0" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$APP/Contents/MacOS/$BIN" \
    Sources/*.swift

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run it:      open '$APP'"
echo "Install it:  cp -r '$APP' /Applications/"
