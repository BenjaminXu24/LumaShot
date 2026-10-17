# LumaShot · 拾光截图

A native macOS screenshot tool for capturing, annotating, and sharing a moment.

[中文说明](README.zh-CN.md) · [Download v0.1.0](https://github.com/BenjaminXu24/LumaShot/releases/tag/v0.1.0) · [Report an issue](https://github.com/BenjaminXu24/LumaShot/issues)

[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-7358e8.svg)](https://github.com/BenjaminXu24/LumaShot/releases)
[![macOS CI](https://github.com/BenjaminXu24/LumaShot/actions/workflows/ci.yml/badge.svg)](https://github.com/BenjaminXu24/LumaShot/actions/workflows/ci.yml)

![LumaShot home](docs/images/home.png)

## Features

- **Capture your way:** region, window, display, and scrolling screenshots.
- **Always available:** global keyboard shortcuts and a menu bar entry.
- **Long screenshots:** automatic downward scrolling or manual frame stitching, overlap matching, and common fixed-header/footer handling.
- **Simple annotations:** arrows, rectangles, ellipses, pen, text, numbered markers, and mosaic; select and move annotations, change colors and line widths, undo/redo, zoom, and pan.
- **Copy or save:** clipboard export and native PNG/JPEG save dialogs, preserving original Retina pixels.
- **Local history:** the latest 100 original screenshots, searchable by capture type or filename, with lightweight thumbnails.
- **Preferences:** capture delay, sound, automatic clipboard copy, login launch, and permission guidance.

Built with SwiftUI, AppKit, ScreenCaptureKit, and Carbon. No third-party runtime dependencies, account, telemetry, or image uploads. The interface is currently in **Simplified Chinese**.

![Annotation editor with a generated practice image](docs/images/editor.png)

## Install

1. Download **[LumaShot-v0.1.0-macOS-universal-notarized.zip](https://github.com/BenjaminXu24/LumaShot/releases/download/v0.1.0/LumaShot-v0.1.0-macOS-universal-notarized.zip)** from [Releases](https://github.com/BenjaminXu24/LumaShot/releases).
2. Extract it and move `LumaShot.app` into Applications.
3. Launch LumaShot and grant **Screen Recording** access when prompted. macOS may call this **Screen & System Audio Recording**. Reopen the app if the system requests it.
4. For automatic scrolling, also grant **Accessibility** access. Manual frame stitching works without Accessibility approval.

Requires **macOS 14 or later**. The universal archive contains **arm64 and x86_64** code for Apple Silicon and Intel Macs.

### Signing

The recommended `*-notarized.zip` is **Developer ID signed and Apple notarized**, with the ticket stapled to the app. Both architectures passed Apple's checks and local Gatekeeper assessment. Download the matching [SHA256SUMS-notarized.txt](https://github.com/BenjaminXu24/LumaShot/releases/download/v0.1.0/SHA256SUMS-notarized.txt) to verify it:

```sh
shasum -a 256 -c SHA256SUMS-notarized.txt
```

Run that command in the directory containing the ZIP and checksum file.

The original `LumaShot-v0.1.0-macOS-universal.zip` and its `SHA256SUMS.txt` remain available unchanged for reproducibility. That original download is ad-hoc signed and not notarized; choose the explicitly named notarized archive for installation.

## Capture

| Mode | Global shortcut | Interaction |
| --- | --- | --- |
| Region | Control + Shift + 1 | Drag a rectangle and release |
| Window | Control + Shift + 2 | Hover to highlight, click to capture |
| Display | Control + Shift + 3 | Capture the display under the pointer |
| Scrolling | Control + Shift + 4 | Select content, then scroll automatically or add frames manually |

Press **Esc** or right-click to cancel region/window selection. Closing the main window leaves the app available in the menu bar; use **Command + Q** or the menu bar's Quit entry to exit.

For scrolling captures, select the scrolling content and avoid stationary sidebars or video. Adjacent frames need overlap. In manual mode, scroll approximately half a viewport and choose **添加当前屏 / Add current frame**, then **完成 / Finish**. Automatic mode pauses at the bottom. If alignment fails, the app keeps the existing result and asks you to scroll back slightly before retrying.

## Annotate and export

| Action | Shortcut |
| --- | --- |
| Copy annotated image | Command + C |
| Save PNG/JPEG | Command + S |
| Undo / redo | Command + Z / Command + Shift + Z |
| Fit / 100% | Command + 0 / Command + 1 |
| Select, arrow, rectangle, ellipse | V / A / R / O |
| Pen, text, number, mosaic, hand | P / T / N / M / H |
| Delete selected annotation | Delete |

Hold **Shift** for constrained arrows, squares, or circles. **Option + drag** pans the canvas. Mosaic changes the exported bitmap pixels. Save defaults to Downloads and lets you choose another location.

Use **体验标注 / Try annotations** to open a generated practice image without screen access. **打开图片 / Open image** imports PNG, JPEG, HEIC, TIFF, or WebP images.

## Local data

Original captures are stored in `~/Library/Application Support/LumaShot/Captures/`. The oldest are removed when more than 100 captures are retained. History deletion removes the app's copy; separately exported images stay in their chosen locations.

**History stores original screenshots, not annotation sessions.** Copy or save the annotated result before closing the editor. The app does not make network requests or upload images.

## Build

Use **Xcode 15+ / Swift 5.9+** on macOS. Initial local validation used Xcode 26.3 and macOS 15.8.1 on Intel.

```sh
git clone https://github.com/BenjaminXu24/LumaShot.git
cd LumaShot
swift test
./scripts/build.sh
open build/LumaShot.app
```

Open `Package.swift` in Xcode to develop. For a verified universal archive and checksum:

```sh
./scripts/package-release.sh
```

Outputs are written to `build/releases/`. The script verifies both architectures, the ad-hoc signature, the embedded MIT license, and ZIP integrity. It does not perform Developer ID signing or notarization.

For optional Developer ID signing, Apple submission, ticket stapling, and Gatekeeper verification, see [the notarization workflow](docs/NOTARIZATION.md). It requires your own valid Developer ID Application identity and a local Keychain authentication profile.

## Validation and limitations

The initial development checks passed **17 automated tests** covering exact stitching pixels, fixed headers/footers, sparse content, repeated/unrelated frames, height limits, native image resolution, annotation coordinates, mosaic, undo/redo, and storage retention. Real ScreenCaptureKit display capture was exercised at **2880 × 1800**; captured test screen pixels were discarded. Native editor Copy/Undo routing and background selection-panel keyboard focus were also checked.

This is an **early-stage release**:

- Third-party automatic scrolling and physical multi-display arrangements need broader real-world testing.
- Animations, virtualized lists, repeated patterns, or insufficient overlap can prevent reliable stitching.
- Long captures are limited to 50,000 pixels in height and approximately 80 megapixels total.
- Annotation sessions are not persisted; the history contains originals.
- The UI is Simplified Chinese; localization contributions are welcome.
- Local and CI builds use ad-hoc signing by default; the recommended release archive is separately Developer ID signed and notarized.

Tests run without screen permissions. See [CONTRIBUTING.md](CONTRIBUTING.md) for an optional local capture smoke check. UI previews can be generated with:

```sh
build/LumaShot.app/Contents/MacOS/LumaShot --render-previews build/previews
```

## Contribute

Bug reports, scrolling compatibility reports, accessibility improvements, and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), check the [changelog](CHANGELOG.md), or [open an issue](https://github.com/BenjaminXu24/LumaShot/issues).

## License

[MIT](LICENSE) · Copyright (c) 2026 BenjaminXu24.
