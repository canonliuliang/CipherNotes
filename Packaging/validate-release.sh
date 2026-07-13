#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/Packaging/release.env"

expected_tag="v${CIPHERNOTES_VERSION}"
release_title="CipherNotes ${CIPHERNOTES_VERSION} - ${CIPHERNOTES_RELEASE_NAME}"

require_text() {
    local file="$1"
    local text="$2"
    if ! grep -Fq "$text" "$file"; then
        echo "Release validation failed: '$file' does not contain '$text'" >&2
        exit 1
    fi
}

require_text "README.md" "Current release: \`${CIPHERNOTES_VERSION}\`"
require_text "README.md" "### ${CIPHERNOTES_VERSION}"
require_text "README.md" "GitHub Releases"
require_text "Website/index.html" "当前发布包 ${CIPHERNOTES_VERSION}"
require_text "Website/index.html" "https://github.com/canonliuliang/CipherNotes/releases/latest"
require_text "docs/index.html" "当前发布包 ${CIPHERNOTES_VERSION}"
require_text "docs/index.html" "https://github.com/canonliuliang/CipherNotes/releases/latest"
require_text "Sources/CipherNotes/Views.swift" "version: \"${CIPHERNOTES_VERSION}\""
require_text "Sources/CipherNotes/Views.swift" "版本与更新"
require_text "Packaging/RELEASE_NOTES.md" "# ${release_title}"
require_text ".github/workflows/release.yml" "Packaging/build-release.sh"

plist_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)
if [ "$plist_version" != "$CIPHERNOTES_VERSION" ]; then
    echo "Release validation failed: Packaging/Info.plist version '$plist_version' != '$CIPHERNOTES_VERSION'" >&2
    exit 1
fi

if ! [[ "$CIPHERNOTES_BUILD" =~ ^[0-9]+$ ]]; then
    echo "Release validation failed: CIPHERNOTES_BUILD must be numeric" >&2
    exit 1
fi

if [ "${1:-}" = "--tag" ]; then
    actual_tag="${2:-}"
    if [ -z "$actual_tag" ]; then
        echo "Release validation failed: --tag requires a tag value" >&2
        exit 1
    fi
    if [ "$actual_tag" != "$expected_tag" ]; then
        echo "Release validation failed: tag '$actual_tag' != '$expected_tag'" >&2
        exit 1
    fi
fi

echo "Release metadata OK: ${release_title} (build ${CIPHERNOTES_BUILD})"
