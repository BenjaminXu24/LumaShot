# Changelog

## Windows [0.1.0](https://github.com/BenjaminXu24/LumaShot/releases/tag/windows-v0.1.0) - 2026-10-17

- Added a native Windows WPF edition with region, visible-window, display, and scrolling capture; global Ctrl+Shift+1–4 shortcuts; and a system tray entry.
- Added automatic scrolling and manual stitching with fixed header/footer handling, pause, retry, cancellation, and image limits.
- Added the annotation editor, actual-pixel mosaic, undo/redo, selection/movement, color/width/font controls, zoom/pan, bitmap/PNG clipboard, and PNG/JPEG export.
- Added original capture history, search, retention, preferences, capture delay, and opt-in login launch.
- Added self-contained x64 and ARM64 installers and portable ZIPs, runtime license notices, checksums, and Windows CI.
- Validation includes 16 cross-platform core checks and native Windows capture/input/rendering/selection/clipboard/history checks. x64 installer install/uninstall is exercised in CI. ARM64 and mixed-DPI multi-monitor hardware need wider testing. Windows binaries are not Authenticode signed.

## [0.1.0] - 2026-10-17

First public, early-stage release of LumaShot / 拾光截图.

### Added

- Native macOS region, window, display, and scrolling screenshots.
- Global Control + Shift + 1–4 shortcuts and a menu bar entry.
- Automatic scrolling with Accessibility approval, plus manual frame stitching.
- Arrows, rectangles, ellipses, freehand drawing, text, numbered markers, and mosaic.
- Selection, moving annotations, undo/redo, colors, line widths, zoom, and pan.
- Clipboard export, PNG/JPEG saving, and local history for the latest 100 captures.
- Native Retina rendering, lightweight history thumbnails, and permission guidance.
- MIT license, bilingual documentation, contributor guidance, and macOS CI.
- Universal Intel / Apple Silicon application archive and SHA-256 checksum.
- Additional Developer ID-signed, Apple-notarized universal archive with a stapled ticket and a separate `SHA256SUMS-notarized.txt`; the original release assets remain unchanged.
- Optional local signing and notarization scripts, Keychain credential setup, and resumable submission workflow.

### Known limitations

- The interface is currently in Simplified Chinese.
- The original archive and default local/CI builds are ad-hoc signed. Use the additional `*-notarized.zip` release asset for Developer ID signing and Apple notarization.
- Third-party automatic scrolling and physical multi-display arrangements need broader real-world testing.
- Scrolling alignment can fail on animations, virtualized lists, or repetitive content.
- History stores original screenshots; annotation sessions are not persisted.

[0.1.0]: https://github.com/BenjaminXu24/LumaShot/releases/tag/v0.1.0
