# Changelog

## Unreleased

## [0.2.2](https://github.com/BenjaminXu24/LumaShot/releases/tag/v0.2.2) - 2026-10-25

### Fixed

- Fixed macOS scrolling capture pause/resume and the last frame being dropped when finishing a capture ([#8](https://github.com/BenjaminXu24/LumaShot/pull/8)).

### Changed

- Mac marketing version is 0.2.2 (`CFBundleShortVersionString`); the build number (`CFBundleVersion`) is 4. The notarized archive name is `LumaShot-v0.2.2-macOS-universal-notarized.zip`.

## [0.2.1](https://github.com/BenjaminXu24/LumaShot/releases/tag/v0.2.1) - 2026-10-25

### Fixed

- Fixed macOS scrolling capture: scrolling, frame stitching, and control bar interaction ([#7](https://github.com/BenjaminXu24/LumaShot/pull/7)).

### Changed

- Mac marketing version is 0.2.1 (`CFBundleShortVersionString`); the build number (`CFBundleVersion`) is 3. The notarized archive name is `LumaShot-v0.2.1-macOS-universal-notarized.zip`.

## [0.2.0](https://github.com/BenjaminXu24/LumaShot/releases/tag/v0.2.0) - 2026-10-25

### Added

- Mac OCR results can be translated in place. DeepSeek (`deepseek-flash`, online) is the default engine; Apple Translation on macOS 15 and later is an optional on-device engine. Languages are Chinese, English, and Filipino. The DeepSeek API key is stored in the macOS Keychain. The first online translation asks for consent. Images are not uploaded and translations are not cached. Windows translation is not included.

### Changed

- Mac marketing version is 0.2.0 (`CFBundleShortVersionString`); the build number (`CFBundleVersion`) is 2. Release scripts read the marketing version from the built app's Info.plist, so the notarized archive name is `LumaShot-v0.2.0-macOS-universal-notarized.zip`.

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
