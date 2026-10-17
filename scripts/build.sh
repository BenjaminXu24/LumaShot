#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
if [[ "${1:-}" == "--universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    TASK_BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LumaShot"
else
    swift build -c release
    TASK_BINARY="$(swift build -c release --show-bin-path)/LumaShot"
fi
TASK_APP="$TASK_ROOT/build/LumaShot.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BINARY" "$TASK_APP/Contents/MacOS/LumaShot"
cp Resources/Info.plist "$TASK_APP/Contents/Info.plist"
cp LICENSE "$TASK_APP/Contents/Resources/LICENSE.txt"
swift scripts/generate-icon.swift "$TASK_ROOT/build"
cp build/AppIcon.icns "$TASK_APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$TASK_APP"
echo "应用已生成：$TASK_APP"
