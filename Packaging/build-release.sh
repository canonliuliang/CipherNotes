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

grep -q "version: \"$CIPHERNOTES_VERSION\"" "$ROOT_DIR/Sources/CipherNotes/Views.swift"
grep -q "Current release: \`$CIPHERNOTES_VERSION\`" "$ROOT_DIR/README.md"
grep -q "当前发布包 $CIPHERNOTES_VERSION" "$ROOT_DIR/Website/index.html"

mkdir -p "$ROOT_DIR/Assets"
if [ ! -f "$ROOT_DIR/Assets/AppIcon.icns" ] || [ ! -f "$ROOT_DIR/Assets/AppIcon-1024.png" ]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    SOURCE_ICON="$ROOT_DIR/Website/icon.png"
    if [ ! -f "$SOURCE_ICON" ]; then
        SOURCE_ICON="$ROOT_DIR/docs/icon.png"
    fi
    if [ ! -f "$SOURCE_ICON" ]; then
        swift Packaging/generate-icon.swift
    else
        sips -s format png -z 16 16 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
        sips -s format png -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
        sips -s format png -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
        sips -s format png -z 64 64 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
        sips -s format png -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
        sips -s format png -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
        sips -s format png -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
        sips -s format png -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
        sips -s format png -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
        sips -s format png -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
        cp "$ICONSET_DIR/icon_512x512@2x.png" "$ROOT_DIR/Assets/AppIcon-1024.png"
        iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Assets/AppIcon.icns"
    fi
fi
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

cp "$ROOT_DIR/README.md" "$OUTPUTS_DIR/使用说明.md"
cp "$ROOT_DIR/Packaging/RELEASE_NOTES.md" "$OUTPUTS_DIR/发布说明.md"
cp "$ROOT_DIR/Assets/AppIcon-1024.png" "$OUTPUTS_DIR/密笺图标.png"
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
