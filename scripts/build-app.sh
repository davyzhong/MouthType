#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MouthType"
BUILD_DIR="$ROOT_DIR/build/debug-app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_SOURCE="$ROOT_DIR/Sources/MouthType/Info.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

printf '==> Building %s\n' "$APP_NAME"
(
  cd "$ROOT_DIR"
  swift build
) >/dev/null

BIN_DIR="$(cd "$ROOT_DIR" && swift build --show-bin-path)"
EXECUTABLE_SOURCE="$BIN_DIR/$APP_NAME"
SQLITE_BUNDLE_SOURCE="$BIN_DIR/SQLite.swift_SQLite.bundle"
TARGET_EXECUTABLE="$MACOS_DIR/$APP_NAME"
TARGET_INFO_PLIST="$CONTENTS_DIR/Info.plist"

if [[ ! -x "$EXECUTABLE_SOURCE" ]]; then
  printf 'error: executable not found at %s\n' "$EXECUTABLE_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  printf 'error: Info.plist not found at %s\n' "$INFO_PLIST_SOURCE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_SOURCE" "$TARGET_EXECUTABLE"
chmod +x "$TARGET_EXECUTABLE"
cp "$INFO_PLIST_SOURCE" "$TARGET_INFO_PLIST"

if [[ -d "$SQLITE_BUNDLE_SOURCE" ]]; then
  cp -R "$SQLITE_BUNDLE_SOURCE" "$RESOURCES_DIR/SQLite.swift_SQLite.bundle"
fi

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"
"$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true

printf '==> App bundle ready: %s\n' "$APP_BUNDLE"
printf '==> Executable: %s\n' "$TARGET_EXECUTABLE"
printf '==> Signature summary:\n'
codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | grep -E 'Identifier=|Signature=|Info.plist='
printf '==> Info.plist keys:\n'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET_INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$TARGET_INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$TARGET_INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$TARGET_INFO_PLIST"
