#!/bin/bash
# Regenerates Resources/AppIcon.icns from Scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swiftc -O Scripts/make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/icon_1024.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
