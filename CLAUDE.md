# ShiftDrop — notes for Claude

macOS menu bar app (LSUIElement, SwiftPM, macOS 14+). Drag files → tap Shift → pie menu at the cursor → drop on a segment to convert or run a tool. Output goes next to the source via `OutputNamer` (never overwrite).

## Commands
- `swift build` / `swift test` — fast loop. All conversion logic is in `ShiftDropCore` and covered by `Tests/ShiftDropCoreTests`.
- `./build.sh` — release `.app`, signed with the first "Apple Development" identity (stable TCC grants).
- UI check without a real drag (debug builds only): `SHIFTDROP_SNAPSHOT=/tmp/x.png [SHIFTDROP_APPEARANCE=dark|light] .build/debug/ShiftDrop --demo-ring <file> [tools] [hoverIndex]` writes the ring panel to a PNG and quits; `--demo-editor crop|bg <image>` does the same for the editors. `Scripts/readme/make.sh` rebuilds the README images in `docs/` from these snapshots (simulated glass, Pillow + NumPy); rerun it after visible UI changes. `screencapture` does not work from the terminal here (no Screen Recording permission). Glass/material backgrounds don't show up in these snapshots.

## How the drag detection works (don't "fix" into needing permissions)
- `DragMonitor`: global **mouse** monitor for `.leftMouseDown` (no Accessibility needed), then a 60 Hz timer only while the button is held: drag pasteboard `changeCount` → file URLs; `NSEvent.modifierFlags` rising edge on Shift. Global key monitors would require Accessibility — avoid.
- `RingPanel` is a non-activating, borderless `NSPanel` at `.popUpMenu` level; a transparent `DropTargetView` on top of the SwiftUI `RingView` is the drag destination and returns `.copy` so Finder leaves the original alone.
- `RingController.dragEnded` hides with a 0.35 s delay because the drop message arrives from the source app after mouse-up.

## Design language
- Ring = a glass dial (Liquid Glass on macOS 26, material fallback). Items sit on the rim, hairline dividers between them, one accent-colored highlight that slides to the hovered item (capped at 64° so small rings don't get a slab of color). The lens in the middle shows the file's Quick Look thumbnail plus the name of the file the drop will create and a one-line hint (`Format.hint`, `Tool.hint`).
- System colors only (`Color.accentColor`, `.primary`/`.secondary`), follows light/dark. It should feel like part of macOS, not a themed app: no custom warm cream/orange palette.
- Labels: format acronyms as-is (PNG), tools in sentence case ("Remove background"). Editors: buttons say what happens ("Save copy").
- Motion: one entrance (scale+fade), the highlight slide, a small dial turn when Shift switches pages. Respects Reduce Motion. Haptic `.alignment` tick on each new hovered item.

## Adding a format or tool
1. `Format` / `Tool` in `ShiftDropCore` (labels, symbol, `isInteractive`).
2. Offer it in `ActionCatalog` (max 8 segments; order = clockwise from 12 o'clock).
3. Implement in the matching converter and route it in `ActionRunner`.
4. Add a test in `ConverterTests`.
Interactive tools (Crop, Add background) open windows from `ActionDispatcher` → `EditorWindows`.

## Gotchas
- ImageIO reads WebP but can't write it → `cwebp` (Homebrew) via `Shell`; the WebP segment is hidden if it's missing.
- `DocumentConverter` is `@MainActor` (AppKit HTML import + text layout).
- `AVAssetWriter.shouldOptimizeForNetworkUse = true` left `.sb-*` temp files next to outputs — keep it off in `VideoCompressor`.
- Apple's HEVC export presets didn't shrink typical clips; `VideoCompressor` sets the bitrate itself.
- Compress deletes its output and reports "already compact" if it isn't smaller.
