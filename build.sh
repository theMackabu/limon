#!/bin/bash
set -euo pipefail

if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

STEPS=6
STEP=0
STEP_NAME=""
STEP_START=0

step() {
    STEP=$((STEP + 1))
    STEP_NAME="$1"
    STEP_START=$SECONDS
    printf "%s[%d/%d]%s %s\n" "$DIM" "$STEP" "$STEPS" "$RESET" "$1"
}

done_step() {
    printf "      %s✓%s %s %s(%ss)%s\n" \
        "$GREEN" "$RESET" "$1" "$DIM" "$((SECONDS - STEP_START))" "$RESET"
}

note() {
    printf "      %s•%s %s\n" "$YELLOW" "$RESET" "$1"
}

fail() {
    printf "\n%serror:%s %s\n" "$RED" "$RESET" "$1" >&2
    exit 1
}

on_error() {
    printf "\n%sfailed%s during step %d/%d: %s\n" "$RED" "$RESET" "$STEP" "$STEPS" "$STEP_NAME" >&2
}
trap on_error ERR

size_of() {
    du -sh "$1" 2>/dev/null | cut -f1 | tr -d ' \t'
}

BUILD="Build"
APP="$BUILD/Limón.app"
BIN="Limon"
DMG="$BUILD/Limon.dmg"
VOLUME="Limon"
BACKGROUND="$BUILD/dmg-background.png"
STAGE="$BUILD/dmg-stage"
LAYOUT="scripts/dmg-window-layout"
RW_DMG="$BUILD/rw.dmg"
ARCH="$(uname -m)"

printf "%sBuilding Limón%s %s(%s)%s\n\n" "$BOLD" "$RESET" "$DIM" "$ARCH" "$RESET"

step "Checking toolchain"
SDK_VERSION=$(xcrun --show-sdk-version)
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
    printf "\n"
    printf "%serror:%s Limón needs the macOS 26 SDK or newer (found %s)\n" "$RED" "$RESET" "$SDK_VERSION" >&2
    printf "       install Xcode 26+, then: sudo xcode-select -s /Applications/Xcode.app\n" >&2
    exit 1
fi
done_step "macOS $SDK_VERSION SDK, $(swiftc --version 2>/dev/null | head -1 | sed 's/ (.*//')"

step "Preparing app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
if [ ! -f AppIcon.icns ]; then
    note "AppIcon.icns missing, generating it"
    swift scripts/make-icon.swift >/dev/null
fi
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
done_step "$APP"

step "Compiling $(ls Sources/*.swift | wc -l | tr -d ' ') source files"
swiftc \
    -O \
    -parse-as-library \
    -target "$ARCH-apple-macosx26.0" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$APP/Contents/MacOS/$BIN" \
    Sources/*.swift
done_step "$BIN binary, $(size_of "$APP/Contents/MacOS/$BIN")"

step "Signing app"
codesign --force --deep --sign - "$APP" 2>/dev/null
done_step "ad-hoc signature, app is $(size_of "$APP")"

step "Rendering disk image background"
swift scripts/make-dmg-background.swift "$BACKGROUND" >/dev/null
done_step "$BACKGROUND"

step "Building disk image"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
cp "$BACKGROUND" "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"
if [ -f "$LAYOUT" ]; then
    cp "$LAYOUT" "$STAGE/.DS_Store"
fi

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
    cp "$MOUNT_DIR/.DS_Store" "$LAYOUT"
    note "styled with Finder, saved layout to $LAYOUT"
else
    note "Finder unavailable, reused saved layout"
fi

sync
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -ov -quiet
rm -f "$RW_DMG"
rm -rf "$STAGE"
done_step "$DMG, $(size_of "$DMG")"

printf "\n%sBuilt in %ss%s\n" "$BOLD" "$SECONDS" "$RESET"
printf "  %sRun%s      open '%s'\n" "$DIM" "$RESET" "$APP"
printf "  %sInstall%s  open '%s'\n" "$DIM" "$RESET" "$DMG"
