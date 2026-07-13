#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="/tmp/ciphernotes-appbuild/密笺.app"
APP_DEST="$HOME/Applications/密笺 Developer.app"

cd "$ROOT_DIR"
"$ROOT_DIR/Packaging/build-release.sh"

mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"
xattr -cr "$APP_DEST" >/dev/null 2>&1 || true

osascript -e 'tell application "密笺" to quit' >/dev/null 2>&1 || true
pkill -x CipherNotes >/dev/null 2>&1 || true
sleep 1

echo "Launching isolated Developer Demo: $APP_DEST"
CIPHERNOTES_ALLOW_CAPTURE=1 "$APP_DEST/Contents/MacOS/CipherNotes" >/tmp/ciphernotes-developer-demo.log 2>&1 &
echo "Developer Demo log: /tmp/ciphernotes-developer-demo.log"
