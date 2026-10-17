#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo 'Set NOTARY_PROFILE to an existing notarytool keychain profile.' >&2
    echo 'Create it interactively with: xcrun notarytool store-credentials LumaShot-notary' >&2
    exit 1
fi

TASK_NEW_SUBMISSION=false
if [[ "$#" -eq 0 ]]; then
    source "$TASK_ROOT/scripts/signing-identity.sh"
    # Validate the certificate type before building or contacting Apple.
    lumashot_resolve_developer_id "${DEVELOPER_ID_APPLICATION:-}" > /dev/null
    ./scripts/build.sh --universal
    mkdir -p "$TASK_ROOT/build/notarization"
    TASK_SESSION="$(mktemp -d "$TASK_ROOT/build/notarization/submission.XXXXXX")"
    ditto "$TASK_ROOT/build/LumaShot.app" "$TASK_SESSION/LumaShot.app"
    TASK_NEW_SUBMISSION=true
elif [[ "$#" -eq 2 && "$1" == '--resume' ]]; then
    TASK_SESSION="$(cd -- "$2" && pwd)"
    if [[ ! -f "$TASK_SESSION/submission.json" ]]; then
        echo 'The resume directory must contain submission.json and its original LumaShot.app.' >&2
        exit 1
    fi
else
    echo 'Usage: NOTARY_PROFILE=profile DEVELOPER_ID_APPLICATION=identity ./scripts/notarize.sh' >&2
    echo 'Resume: NOTARY_PROFILE=profile ./scripts/notarize.sh --resume build/notarization/submission.XXXXXX' >&2
    exit 64
fi

TASK_APP="$TASK_SESSION/LumaShot.app"
codesign --verify --deep --strict "$TASK_APP"
TASK_SIGNATURE="$(codesign --display --verbose=4 "$TASK_APP" 2>&1)"
if [[ "$TASK_SIGNATURE" != *'Authority=Developer ID Application:'* ||
      "$TASK_SIGNATURE" != *'runtime)'* || "$TASK_SIGNATURE" != *'Timestamp='* ]]; then
    echo 'The application must have a Developer ID Application signature, Hardened Runtime, and secure timestamp.' >&2
    exit 1
fi
TASK_ARCHS="$(lipo -archs "$TASK_APP/Contents/MacOS/LumaShot")"
if [[ "$TASK_ARCHS" != *arm64* || "$TASK_ARCHS" != *x86_64* ]]; then
    echo 'The notarization package must contain both arm64 and x86_64.' >&2
    exit 1
fi

if [[ "$TASK_NEW_SUBMISSION" == true ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_SESSION/submission.zip"
    xcrun notarytool submit "$TASK_SESSION/submission.zip" \
        --keychain-profile "$NOTARY_PROFILE" --output-format json > "$TASK_SESSION/submission.json"
fi

TASK_SUBMISSION_ID="$(python3 - "$TASK_SESSION/submission.json" <<'PY'
import json, sys, uuid
with open(sys.argv[1]) as source:
    submission = json.load(source)
print(uuid.UUID(submission['id']))
PY
)"
printf 'Apple submission: %s\nLocal session: %s\n' "$TASK_SUBMISSION_ID" "$TASK_SESSION"
TASK_WAIT_EXIT=0
xcrun notarytool wait "$TASK_SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" \
    --timeout 20m --output-format json > "$TASK_SESSION/status.json" || TASK_WAIT_EXIT=$?
TASK_STATUS="$(python3 - "$TASK_SESSION/status.json" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as source:
        print(json.load(source).get('status', ''))
except (OSError, ValueError):
    print('')
PY
)"
if [[ "$TASK_STATUS" != Accepted && "$TASK_STATUS" != Invalid && "$TASK_STATUS" != Rejected ]]; then
    echo "Waiting did not return a terminal status (exit $TASK_WAIT_EXIT); Apple may still be processing." >&2
    echo "Resume this exact session using --resume \"$TASK_SESSION\"; do not upload it again." >&2
    exit 1
fi
xcrun notarytool log "$TASK_SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" "$TASK_SESSION/notary-log.json"
if [[ "$TASK_STATUS" != Accepted ]]; then
    echo "Notarization status: $TASK_STATUS. Review $TASK_SESSION/notary-log.json" >&2
    exit 1
fi

xcrun stapler staple "$TASK_APP"
xcrun stapler validate "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
spctl --assess --type execute --verbose=4 "$TASK_APP"
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")"
if [[ ! "$TASK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
    echo "Invalid application version: $TASK_VERSION" >&2
    exit 1
fi
TASK_ARCHIVE="LumaShot-v${TASK_VERSION}-macOS-universal-notarized.zip"
ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_SESSION/$TASK_ARCHIVE"
unzip -tq "$TASK_SESSION/$TASK_ARCHIVE"
cd "$TASK_SESSION"
shasum -a 256 "$TASK_ARCHIVE" > SHA256SUMS.txt
printf 'Accepted, stapled, and Gatekeeper-verified: %s/%s\n' "$TASK_SESSION" "$TASK_ARCHIVE"
echo 'No GitHub release assets have been changed by this script.'
