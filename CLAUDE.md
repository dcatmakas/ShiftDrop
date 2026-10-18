# ShiftDrop — notes for Claude

macOS menu bar app (LSUIElement, SwiftPM, macOS 14+). Drag files → tap Shift → pie menu at the cursor → drop on a segment to convert or run a tool. Output goes next to the source via `OutputNamer` (never overwrite).

## Commands
- `swift build` / `swift test` — fast loop. All conversion logic is in `ShiftDropCore` and covered by `Tests/ShiftDropCoreTests`.
- `./build.sh` — release `.app`, signed with the first "Apple Development" identity (stable TCC grants).
- UI check without a real drag (debug builds only): `SHIFTDROP_SNAPSHOT=/tmp/x.png .build/debug/ShiftDrop --demo-ring <file> [tools] [hoverIndex]` writes the ring panel to a PNG and quits. `screencapture` does not work from the terminal here (no Screen Recording permission). Glass/material backgrounds don't show up in these snapshots.

## How the drag detection works (don't "fix" into needing permissions)
- `DragMonitor`: global **mouse** monitor for `.leftMouseDown` (no Accessibility needed), then a 60 Hz timer only while the button is held: drag pasteboard `changeCount` → file URLs; `NSEvent.modifierFlags` rising edge on Shift. Global key monitors would require Accessibility — avoid.
- `RingPanel` is a non-activating, borderless `NSPanel` at `.popUpMenu` level; a transparent `DropTargetView` on top of the SwiftUI `RingView` is the drag destination and returns `.copy` so Finder leaves the original alone.
- `RingController.dragEnded` hides with a 0.35 s delay because the drop message arrives from the source app after mouse-up.

## Adding a format or tool
1. `Format` / `Tool` in `ShiftDropCore` (labels, symbol, `isInteractive`).
2. Offer it in `ActionCatalog` (max 8 segments; order = clockwise from 12 o'clock).
3. Implement in the matching converter and route it in `ActionRunner`.
4. Add a test in `ConverterTests`.
Interactive tools (Crop, Add BG) open windows from `ActionDispatcher` → `EditorWindows`.

## Gotchas
- ImageIO reads WebP but can't write it → `cwebp` (Homebrew) via `Shell`; the WebP segment is hidden if it's missing.
- `DocumentConverter` is `@MainActor` (AppKit HTML import + text layout).
- `AVAssetWriter.shouldOptimizeForNetworkUse = true` left `.sb-*` temp files next to outputs — keep it off in `VideoCompressor`.
- Apple's HEVC export presets didn't shrink typical clips; `VideoCompressor` sets the bitrate itself.
- Compress deletes its output and reports "already compact" if it isn't smaller.
