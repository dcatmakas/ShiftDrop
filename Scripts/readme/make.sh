#!/bin/bash
# Regenerates the README images in docs/ from the real UI.
#
# Runs a debug build in snapshot mode (the app draws its own windows into PNGs, so no
# Screen Recording permission is needed), then paints simulated Liquid Glass and a
# wallpaper behind them. Needs python3 with Pillow and NumPy.
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/samples" "$WORK/shots" docs

swift build
python3 -I Scripts/readme/samples.py "$WORK"

snap() { # output appearance args...
    local out=$1 appearance=$2; shift 2
    SHIFTDROP_DEMO_CROP=square SHIFTDROP_SNAPSHOT="$out" SHIFTDROP_APPEARANCE="$appearance" \
        SHIFTDROP_SNAPSHOT_GLASS=clear .build/debug/ShiftDrop "$@" &
    local pid=$!
    for _ in $(seq 1 40); do kill -0 $pid 2>/dev/null || break; sleep 0.25; done
    kill $pid 2>/dev/null || true
}

for appearance in light dark; do
    snap "$WORK/shots/ring_convert_$appearance.png" $appearance --demo-ring "$WORK/samples/Report.pdf" 1
    snap "$WORK/shots/ring_tools_$appearance.png" $appearance --demo-ring "$WORK/samples/Mountains.jpg" tools 3
    snap "$WORK/shots/ed_crop_$appearance.png" $appearance --demo-editor crop "$WORK/samples/Mountains.jpg"
    snap "$WORK/shots/ed_bg_$appearance.png" $appearance --demo-editor bg "$WORK/samples/Mountains.jpg"
done
qlmanage -t -s 256 -o "$WORK/shots" "$WORK/samples/Report.pdf" "$WORK/samples/Mountains.jpg" >/dev/null 2>&1

python3 -I Scripts/readme/compose.py "$WORK" docs
sips -s format png -z 256 256 Resources/AppIcon.icns --out docs/icon.png >/dev/null
echo "Updated docs/"
