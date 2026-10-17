# Contributing to LumaShot

English and Chinese contributions are welcome. The project has native macOS and Windows applications, and useful first contributions include scrolling compatibility reports, physical multi-display testing, accessibility improvements, and localization.

## Build and test

### Windows

Follow the [Windows source build guide](Windows/README.md#开发与验证) for prerequisites and a fresh clone. Use PowerShell 7.2+ with the .NET 10 SDK:

```powershell
pwsh -NoProfile -File .\Windows\scripts\doctor.ps1
pwsh -NoProfile -File .\Windows\scripts\build.ps1 -Run
# Quit LumaShot from the system tray before running native checks.
pwsh -NoProfile -File .\Windows\scripts\test.ps1
```

Native checks use the mouse and clipboard and need an unlocked interactive desktop. `test.ps1 -CoreOnly` runs the pixel and annotation model checks without UI. Packaging also requires Inno Setup 6.3+; `package.ps1 -Runtime win-x64` or `-Runtime win-arm64` writes self-contained packages to `build/windows-releases/`. The Windows version is defined in `Windows/Directory.Build.props`. Run the Windows checks for Windows changes and report OS, architecture, display scaling, and target app for scrolling issues.

### macOS

Use macOS 14 or later with Xcode 15 / Swift 5.9 or later. The initial release was built locally with Xcode 26.3 on macOS 15.8.1.

```sh
git clone https://github.com/BenjaminXu24/LumaShot.git
cd LumaShot
swift build
swift test
./scripts/build.sh
open build/LumaShot.app
```

Open `Package.swift` in Xcode for debugging. Tests exercise bitmap rendering, stitching, and local storage; they do not request Screen Recording or Accessibility approval. Actual capture checks belong in a local desktop session with the appropriate approval:

```sh
mkdir -p build
swiftc -parse-as-library -swift-version 5 -o build/CaptureSmoke Sources/LumaShot/Models.swift Sources/LumaShot/Capture/*.swift scripts/CaptureSmoke.swift
build/CaptureSmoke
```

This optional check discards captured pixels and exits with code 77 if Screen Recording is not already approved; it does not request permission.

## Changes

1. Open an issue for substantial behavior or architecture changes so the approach can be discussed.
2. Create a focused branch and describe the problem, change, and validation in your pull request.
3. Keep geometry in original image pixels and preserve Retina resolution when touching rendering.
4. Add regression coverage for a reproducible bug; UI-only changes can use before/after images.
5. Run the relevant platform's checks and build the app. Include OS version, CPU architecture, and target app when reporting scrolling behavior.

Use generated demo images or sanitized fixtures in screenshots and tests. Do not include captured personal information, signing certificates, credentials, or unrelated local files.

## Repository layout

- `Sources/LumaShot/Capture`: ScreenCaptureKit, selection panels, scrolling controls, and stitching.
- `Sources/LumaShot/Editor`: annotation state, renderer, canvas, and editor window.
- `Sources/LumaShot/Services`: global shortcuts, capture history, and export.
- `Tests/LumaShotTests`: stitching, rendering, and storage regression tests.
- `scripts`: application packaging, icon generation, and an optional capture smoke check.
- `Windows`: WPF app, shared pixel/annotation models, tests, installer, and PowerShell build scripts.

## Releases

The application version lives in `Resources/Info.plist`; `AppVersion.current` reads it in the packaged app. Update the development fallback in `Models.swift` and add a changelog entry when changing versions.

```sh
swift test
./scripts/package-release.sh
```

The script builds both architectures, verifies the signature and embedded MIT license, and generates a versioned ZIP plus `SHA256SUMS.txt` under `build/releases/`. Tag the reviewed commit, then publish those files in a GitHub Release. Builds are ad-hoc signed; do not describe them as notarized.

By contributing, you agree that your contribution is available under the project's [MIT license](LICENSE). Contributors retain copyright in their own work. Please be respectful and keep discussions focused on the project.
