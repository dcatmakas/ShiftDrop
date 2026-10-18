#!/bin/bash
# Builds ShiftDrop in release mode and wraps it in ShiftDrop.app.
#
# Signing: uses the first "Apple Development" identity in the keychain so that
# macOS remembers folder permissions between builds. Override with
# SIGN_IDENTITY="..." ./build.sh, or SIGN_IDENTITY=- for ad-hoc signing.
set -euo pipefail

cd "$(dirname "$0")"

echo "Building ShiftDrop..."
swift build -c release

APP_DIR="ShiftDrop.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/ShiftDrop "$APP_DIR/Contents/MacOS/"
cp Resources/Info.plist "$APP_DIR/Contents/"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Apple Development" | head -1 | awk '{print $2}' || true)
fi
SIGN_IDENTITY=${SIGN_IDENTITY:--}

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo ""
echo "Build complete: $APP_DIR (signed with: $SIGN_IDENTITY)"
echo "Run with: open $APP_DIR"
