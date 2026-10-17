#!/bin/bash
# Sourced by build.sh. Resolves only a valid Developer ID Application identity
# that includes its private key in the current user's keychain search list.
lumashot_resolve_developer_id() {
    local task_requested="${1:-}"
    local task_resolved
    if [[ -z "$task_requested" ]]; then
        echo 'Set DEVELOPER_ID_APPLICATION to a Developer ID Application certificate name or SHA-1 fingerprint.' >&2
        return 1
    fi
    task_resolved="$(security find-identity -v -p codesigning | awk -v requested="$task_requested" '
        index($0, "\"Developer ID Application:") &&
        (index($0, "\"" requested "\"") || toupper($2) == toupper(requested)) {
            print $2
            exit
        }
    ')"
    if [[ -z "$task_resolved" ]]; then
        echo 'No matching valid Developer ID Application identity with a private key was found.' >&2
        echo 'Apple Development, Apple Distribution, and ad-hoc identities cannot be used for this workflow.' >&2
        return 1
    fi
    printf '%s\n' "$task_resolved"
}
