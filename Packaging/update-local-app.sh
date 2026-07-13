#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="/tmp/ciphernotes-appbuild/密笺.app"
APP_DEST="/Applications/密笺.app"
PKG_PATH="$ROOT_DIR/outputs/密笺安装器.pkg"

cd "$ROOT_DIR"

echo "==> Building CipherNotes release outputs..."
"$ROOT_DIR/Packaging/build-release.sh"

if [ ! -d "$APP_SOURCE" ]; then
    echo "Local update failed: built app not found at $APP_SOURCE" >&2
    exit 1
fi

echo "==> Closing running CipherNotes app if needed..."
osascript -e 'tell application "密笺" to quit' >/dev/null 2>&1 || true
sleep 1

echo "==> Installing app to $APP_DEST"
if ditto "$APP_SOURCE" "$APP_DEST"; then
    xattr -cr "$APP_DEST" >/dev/null 2>&1 || true
else
    echo "Direct app copy failed. Trying installer package instead..." >&2
    if [ ! -f "$PKG_PATH" ]; then
        echo "Local update failed: installer package not found at $PKG_PATH" >&2
        exit 1
    fi
    ADMIN_PKG="/tmp/ciphernotes-local-update.pkg"
    cp "$PKG_PATH" "$ADMIN_PKG"
    osascript \
        -e "set packagePath to POSIX path of \"$ADMIN_PKG\"" \
        -e 'do shell script "installer -pkg " & quoted form of packagePath & " -target /" with administrator privileges'
fi

echo "==> Verifying installed app..."
codesign --verify --strict "$APP_DEST"

echo "==> Opening CipherNotes..."
open "$APP_DEST"

echo "Local CipherNotes update complete."
