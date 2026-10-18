#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$HOME/Library/Caches/GuoguoKan-build"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
APP_DIR="$BUILD_DIR/交付/果果看.app"
swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --arch arm64
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --arch arm64 --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp -X "$BIN_DIR/GuoguoKan" "$APP_DIR/Contents/MacOS/GuoguoKan"
cp -X "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -X "$PROJECT_DIR/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
mkdir -p "$PROJECT_DIR/交付"
ditto --norsrc --noextattr --noacl "$APP_DIR" "$PROJECT_DIR/交付/果果看.app"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP_DIR" "$PROJECT_DIR/交付/GuoguoKan-$VERSION-arm64.zip"
echo "已生成果果看.app"
