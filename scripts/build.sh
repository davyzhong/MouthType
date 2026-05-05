#!/usr/bin/env bash
# MouthType 统一构建脚本
# 用法：./scripts/build.sh [debug|release] [--clean]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MouthType"
BUILD_MODE="${1:-debug}"
CLEAN_BUILD=false
ENTITLEMENTS="$ROOT_DIR/Sources/MouthType/MouthType.entitlements"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN_BUILD=true
            ;;
        debug|release)
            BUILD_MODE="$arg"
            ;;
    esac
done

# Set build directories and flags based on mode
if [[ "$BUILD_MODE" == "release" ]]; then
    BUILD_CONFIG="release"
    BUILD_DIR="$ROOT_DIR/.build/release"
    APP_BUNDLE="$ROOT_DIR/build/MouthType.app"
    SWIFT_FLAGS="-c release"
else
    BUILD_CONFIG="debug"
    BUILD_DIR="$ROOT_DIR/.build/debug"
    APP_BUNDLE="$ROOT_DIR/build/debug-app/MouthType.app"
    SWIFT_FLAGS=""
fi

echo "==> Building MouthType ($BUILD_CONFIG mode)"

# Clean if requested
if [[ "$CLEAN_BUILD" == "true" ]]; then
    echo "==> Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Build
cd "$ROOT_DIR"
if [[ -n "$SWIFT_FLAGS" ]]; then
    swift build $SWIFT_FLAGS
else
    swift build
fi

# Create app bundle
echo "==> Creating app bundle..."

# Clean old bundle
if [[ -d "$APP_BUNDLE" ]]; then
    rm -rf "$APP_BUNDLE"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Sources/MouthType/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy SQLite bundle if exists
SQLITE_BUNDLE="$BUILD_DIR/SQLite.swift_SQLite.bundle"
if [[ -d "$SQLITE_BUNDLE" ]]; then
    cp -R "$SQLITE_BUNDLE" "$APP_BUNDLE/Contents/Resources/SQLite.swift_SQLite.bundle"
fi

# Copy models (release mode only)
if [[ "$BUILD_CONFIG" == "release" ]]; then
    echo "==> Copying models to bundle..."

    # Whisper models
    WHISPER_MODEL_SOURCE="$ROOT_DIR/Resources/whisper-models"
    WHISPER_MODEL_DEST="$APP_BUNDLE/Contents/Resources/whisper-models"
    if [[ -d "$WHISPER_MODEL_SOURCE" ]]; then
        mkdir -p "$WHISPER_MODEL_DEST"
        cp -R "$WHISPER_MODEL_SOURCE"/* "$WHISPER_MODEL_DEST/" 2>/dev/null || true
    fi

    # SenseVoice models
    SENSEVOICE_MODEL_SOURCE="$ROOT_DIR/Resources/sensevoice-models"
    SENSEVOICE_MODEL_DEST="$APP_BUNDLE/Contents/Resources/sensevoice-models"
    if [[ -d "$SENSEVOICE_MODEL_SOURCE" ]]; then
        mkdir -p "$SENSEVOICE_MODEL_DEST"
        cp -R "$SENSEVOICE_MODEL_SOURCE"/* "$SENSEVOICE_MODEL_DEST/" 2>/dev/null || true
    fi
fi

# Sign with entitlements (release) or ad-hoc (debug)
if [[ "$BUILD_CONFIG" == "release" ]]; then
    echo "==> Signing with entitlements..."
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
    echo "==> Ad-hoc signing..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

# Verify signature
echo "==> Verifying signature..."
codesign --verify --deep --strict "$APP_BUNDLE" 2>&1 | head -5

# Register with LaunchServices (debug mode only)
if [[ "$BUILD_CONFIG" == "debug" ]]; then
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [[ -x "$LSREGISTER" ]]; then
        "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
    fi
fi

echo ""
echo "==> Build complete!"
echo "    Bundle: $APP_BUNDLE"
echo "    Executable: $APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""

# Print signature summary
echo "==> Signature summary:"
codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | grep -E 'Identifier=|Signature=|Info.plist=' || true
