#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/ciphernotes-release-build"
APPBUILD_DIR="/tmp/ciphernotes-appbuild"
APP_PATH="$APPBUILD_DIR/密笺.app"
OUTPUTS_DIR="$ROOT_DIR/outputs"
PRODUCTBUILD_LOG="/tmp/ciphernotes-productbuild.log"
ICONBUILD_DIR="/tmp/ciphernotes-iconbuild"
ICONSET_DIR="$ICONBUILD_DIR/AppIcon.iconset"

cd "$ROOT_DIR"

source "$ROOT_DIR/Packaging/release.env"

"$ROOT_DIR/Packaging/validate-release.sh"

mkdir -p "$ROOT_DIR/Assets"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
swift Packaging/generate-icon.swift
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Assets/AppIcon.icns"
swift test --scratch-path /tmp/ciphernotes-test
swift build -c release --scratch-path "$BUILD_DIR"

rm -rf "$APPBUILD_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/release/CipherNotes" "$APP_PATH/Contents/MacOS/CipherNotes"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CIPHERNOTES_VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CIPHERNOTES_BUILD" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
chmod +x "$APP_PATH/Contents/MacOS/CipherNotes"
xattr -cr "$APP_PATH" >/dev/null 2>&1 || true
codesign --force --sign - "$APP_PATH"

mkdir -p "$OUTPUTS_DIR"
mkdir -p "$OUTPUTS_DIR/media"

cp "$ROOT_DIR/README.md" "$OUTPUTS_DIR/使用说明.md"
cp "$ROOT_DIR/Packaging/RELEASE_NOTES.md" "$OUTPUTS_DIR/发布说明.md"
cp "$ROOT_DIR/Assets/AppIcon-1024.png" "$OUTPUTS_DIR/密笺图标.png"
cp "$ROOT_DIR/Website/media/app-screenshot.jpg" "$OUTPUTS_DIR/media/app-screenshot.jpg"
cp "$ROOT_DIR/Website/icon.png" "$OUTPUTS_DIR/icon.png"
cp "$ROOT_DIR/Website/index.html" "$ROOT_DIR/docs/index.html"
sed 's|../outputs/密笺安装器.pkg|密笺安装器.pkg|g; s|../outputs/密笺-macOS.zip|密笺-macOS.zip|g' "$ROOT_DIR/Website/index.html" > "$OUTPUTS_DIR/产品介绍.html"

rm -f "$OUTPUTS_DIR/密笺安装器.pkg" "$OUTPUTS_DIR/密笺-macOS.zip"
if productbuild --component "$APP_PATH" /Applications "$OUTPUTS_DIR/密笺安装器.pkg" >"$PRODUCTBUILD_LOG" 2>&1; then
    grep -v '^write: Permission denied$' "$PRODUCTBUILD_LOG" || true
else
    cat "$PRODUCTBUILD_LOG" >&2
    exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUTS_DIR/密笺-macOS.zip"

codesign --verify --strict "$APP_PATH"
pkgutil --payload-files "$OUTPUTS_DIR/密笺安装器.pkg" >/dev/null
find "$ROOT_DIR" -name .DS_Store -delete 2>/dev/null || true

echo "Release outputs updated in $OUTPUTS_DIR"
