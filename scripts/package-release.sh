#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
./scripts/build.sh --universal
TASK_APP="$TASK_ROOT/build/LumaShot.app"
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")"
if [[ ! "$TASK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
    echo "Invalid application version: $TASK_VERSION" >&2
    exit 1
fi
TASK_ARCHS="$(lipo -archs "$TASK_APP/Contents/MacOS/LumaShot")"
if [[ "$TASK_ARCHS" != *arm64* || "$TASK_ARCHS" != *x86_64* ]]; then
    echo "Release requires both arm64 and x86_64: $TASK_ARCHS" >&2
    exit 1
fi
codesign --verify --deep --strict "$TASK_APP"
cmp LICENSE "$TASK_APP/Contents/Resources/LICENSE.txt"
TASK_RELEASE_DIR="$TASK_ROOT/build/releases"
TASK_ARCHIVE="LumaShot-v${TASK_VERSION}-macOS-universal.zip"
mkdir -p "$TASK_RELEASE_DIR"
ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_RELEASE_DIR/$TASK_ARCHIVE"
unzip -tq "$TASK_RELEASE_DIR/$TASK_ARCHIVE"
cd "$TASK_RELEASE_DIR"
shasum -a 256 "$TASK_ARCHIVE" > SHA256SUMS.txt
echo "Release package: $TASK_RELEASE_DIR/$TASK_ARCHIVE"
cat SHA256SUMS.txt
