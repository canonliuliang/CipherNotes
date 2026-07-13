#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/ciphernotes-release-build"
APPBUILD_DIR="/tmp/ciphernotes-appbuild"
APP_PATH="$APPBUILD_DIR/密笺.app"
DEVELOPER_APP_PATH="$APPBUILD_DIR/密笺 Developer.app"
OUTPUTS_DIR="$ROOT_DIR/outputs"
PRODUCTBUILD_LOG="/tmp/ciphernotes-productbuild.log"
ICONBUILD_DIR="/tmp/ciphernotes-iconbuild"
ICONSET_DIR="$ICONBUILD_DIR/AppIcon.iconset"
DEVELOPER_ICONSET_DIR="$ICONBUILD_DIR/DeveloperIcon.iconset"

cd "$ROOT_DIR"

source "$ROOT_DIR/Packaging/release.env"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

"$ROOT_DIR/Packaging/validate-release.sh"

mkdir -p "$ROOT_DIR/Assets"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
swift Packaging/generate-icon.swift
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Assets/AppIcon.icns"
iconutil -c icns "$DEVELOPER_ICONSET_DIR" -o "$ROOT_DIR/Assets/DeveloperAppIcon.icns"
swift test --scratch-path /tmp/ciphernotes-test
swift build -c release --scratch-path "$BUILD_DIR"

rm -rf "$APPBUILD_DIR"

make_app() {
    local app_path="$1"
    local display_name="$2"
    local bundle_id="$3"
    mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
    cp "$BUILD_DIR/release/CipherNotes" "$app_path/Contents/MacOS/CipherNotes"
    cp "$ROOT_DIR/Packaging/Info.plist" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display_name" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $display_name" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CIPHERNOTES_VERSION" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CIPHERNOTES_BUILD" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleBuildDate $BUILD_DATE" "$app_path/Contents/Info.plist"
    local icon_path="$ROOT_DIR/Assets/AppIcon.icns"
    if [ "$bundle_id" = "app.ciphernotes.local.developer" ]; then
        icon_path="$ROOT_DIR/Assets/DeveloperAppIcon.icns"
    fi
    cp "$icon_path" "$app_path/Contents/Resources/AppIcon.icns"
    chmod +x "$app_path/Contents/MacOS/CipherNotes"
    xattr -cr "$app_path" >/dev/null 2>&1 || true
    codesign --force --sign - "$app_path"
}

make_app "$APP_PATH" "密笺" "app.ciphernotes.local"
make_app "$DEVELOPER_APP_PATH" "密笺 Developer" "app.ciphernotes.local.developer"

mkdir -p "$OUTPUTS_DIR"
mkdir -p "$OUTPUTS_DIR/media"

cp "$ROOT_DIR/README.md" "$OUTPUTS_DIR/使用说明.md"
cp "$ROOT_DIR/Packaging/RELEASE_NOTES.md" "$OUTPUTS_DIR/发布说明.md"
cp "$ROOT_DIR/Assets/AppIcon-1024.png" "$OUTPUTS_DIR/密笺图标.png"
cp "$ROOT_DIR/Website/media/app-screenshot.jpg" "$OUTPUTS_DIR/media/app-screenshot.jpg"
cp "$ROOT_DIR/Website/icon.png" "$OUTPUTS_DIR/icon.png"
cp "$ROOT_DIR/Website/index.html" "$ROOT_DIR/docs/index.html"
sed "s|../outputs/密笺安装器.pkg|密笺-${CIPHERNOTES_VERSION}-普通版.pkg|g; s|../outputs/密笺-macOS.zip|密笺-${CIPHERNOTES_VERSION}-普通版.zip|g" "$ROOT_DIR/Website/index.html" > "$OUTPUTS_DIR/产品介绍.html"

NORMAL_PKG="$OUTPUTS_DIR/密笺-${CIPHERNOTES_VERSION}-普通版.pkg"
DEVELOPER_PKG="$OUTPUTS_DIR/密笺-Developer-${CIPHERNOTES_VERSION}.pkg"
NORMAL_ZIP="$OUTPUTS_DIR/密笺-${CIPHERNOTES_VERSION}-普通版.zip"
DEVELOPER_ZIP="$OUTPUTS_DIR/密笺-Developer-${CIPHERNOTES_VERSION}.zip"
# Remove pre-1.0.7 single-app artifacts so outputs always contains exactly
# one public package and one isolated Developer package.
rm -f "$NORMAL_PKG" "$DEVELOPER_PKG" "$NORMAL_ZIP" "$DEVELOPER_ZIP" \
    "$OUTPUTS_DIR/密笺安装器.pkg" "$OUTPUTS_DIR/密笺-macOS.zip"
if productbuild --component "$APP_PATH" /Applications "$NORMAL_PKG" >"$PRODUCTBUILD_LOG" 2>&1; then
    grep -v '^write: Permission denied$' "$PRODUCTBUILD_LOG" || true
else
    cat "$PRODUCTBUILD_LOG" >&2
    exit 1
fi
if productbuild --component "$DEVELOPER_APP_PATH" /Applications "$DEVELOPER_PKG" >>"$PRODUCTBUILD_LOG" 2>&1; then
    grep -v '^write: Permission denied$' "$PRODUCTBUILD_LOG" || true
else
    cat "$PRODUCTBUILD_LOG" >&2
    exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NORMAL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$DEVELOPER_APP_PATH" "$DEVELOPER_ZIP"

codesign --verify --strict "$APP_PATH"
codesign --verify --strict "$DEVELOPER_APP_PATH"
pkgutil --payload-files "$NORMAL_PKG" >/dev/null
pkgutil --payload-files "$DEVELOPER_PKG" >/dev/null
find "$ROOT_DIR" -name .DS_Store -delete 2>/dev/null || true

echo "Release outputs updated in $OUTPUTS_DIR"
