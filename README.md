# ShiftDrop

Convert and edit files without opening an app: start dragging a file, tap **⇧ Shift**, and drop it on a ring of formats and tools that appears around the cursor.

The result is saved next to the original (`Photo.png` → `Photo.jpg`, `Photo Cropped.png`, …). Nothing is ever overwritten.

## How to use

1. Start dragging one or more files in Finder or on the Desktop.
2. Tap **⇧ Shift**. The **Convert** ring opens around the cursor.
3. Tap **⇧ Shift** again to switch to **Tools**, and again to switch back.
4. Drop on a segment. Drop in the middle, or anywhere else, to cancel.

## What it can do

| Input | Convert | Tools |
| --- | --- | --- |
| Images (PNG, JPG, HEIC, WebP, AVIF, TIFF, GIF, BMP) | PNG, JPG, WebP¹, HEIC, AVIF, PDF, TIFF, TXT (text recognition), GIF, BMP | Compress, Strip EXIF, Copy Text, Remove BG, Add BG, Crop, ZIP · several images: Make PDF |
| PDF | DOCX, JPG, PNG, TXT (one image per page) | Compress, Copy Text, Split, Merge (several PDFs), ZIP |
| Documents (DOCX, DOC, RTF, ODT, HTML, TXT, MD) | PDF, DOCX, RTF, TXT, HTML, ODT | Copy Text, ZIP |
| Video (MP4, MOV, M4V) | MP4, MOV, M4A (audio only), GIF | Compress (HEVC), Mute, ZIP |
| Audio (M4A, MP3, WAV, AIFF, CAF) | M4A, WAV, AIFF, CAF | ZIP |
| Anything else, folders | – | ZIP |

¹ WebP output needs `cwebp`: `brew install webp`. Everything else uses frameworks built into macOS (ImageIO, PDFKit, Vision, AVFoundation), and runs on your Mac.

## Permissions

ShiftDrop does **not** need Accessibility or Input Monitoring. It watches mouse clicks with a global mouse monitor and only reads the drag pasteboard and the Shift key while the mouse button is down.

The first time it saves into Desktop, Documents or Downloads, macOS asks for access to that folder.

## Build

Requires macOS 14+ and Xcode 15+ (Swift 5.9+).

```bash
./build.sh          # release build → ShiftDrop.app
open ShiftDrop.app
```

`build.sh` signs with your first "Apple Development" certificate so macOS remembers folder permissions between builds. Use `SIGN_IDENTITY=- ./build.sh` for ad-hoc signing.

```bash
swift test          # conversion tests
SHIFTDROP_SAMPLE_VIDEO=~/Movies/clip.mp4 swift test --filter MediaSmokeTests   # video/audio smoke test
```

### Debug helpers

A debug build can show the ring without a drag, which is handy for UI work:

```bash
swift build
.build/debug/ShiftDrop --demo-ring ~/Desktop/photo.png          # convert ring
.build/debug/ShiftDrop --demo-ring ~/Desktop/photo.png tools 2  # tools ring, 3rd segment hovered
SHIFTDROP_SNAPSHOT=/tmp/ring.png .build/debug/ShiftDrop --demo-ring ~/Desktop/photo.png  # save a PNG and quit
```

## Layout

```
Sources/ShiftDropCore/   conversion + tool logic, no UI (unit tested)
Sources/ShiftDrop/
  Ring/                  drag detection, ring panel and view
  Editors/               Crop and Add BG windows
  Support/               action dispatch, toast
Scripts/make-icon.sh     regenerates Resources/AppIcon.icns
```
