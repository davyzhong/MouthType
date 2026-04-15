#!/bin/bash
# 构建 MouthType 并正确签名 entitlements

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
ENTITLEMENTS="$PROJECT_DIR/Sources/MouthType/MouthType.entitlements"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/build/MouthType.app"
MODEL_DIR="$PROJECT_DIR/Resources/whisper-models"
APP_MODEL_DIR="$APP_BUNDLE/Contents/Resources/whisper-models"
BUNDLE_ID="com.mouthtype.app"

echo "=== 清理旧版本应用 ==="
# 删除旧的 app bundle
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
    echo "已删除旧的 App Bundle"
fi

# 终止正在运行的应用
if pgrep -x "MouthType" > /dev/null; then
    killall MouthType 2>/dev/null || true
    echo "已终止正在运行的 MouthType 进程"
fi

# 清除应用的 Preferences（UserDefaults）
if [ -f "$HOME/Library/Preferences/$BUNDLE_ID.plist" ]; then
    rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    echo "已清除应用 Preferences"
fi

# 清除应用的 Cache
CACHE_DIR="$HOME/Library/Caches/$BUNDLE_ID"
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "已清除应用 Cache"
fi

# 清除应用的应用支持目录（包含模型文件等）
APP_SUPPORT_DIR="$HOME/Library/Application Support/MouthType"
if [ -d "$APP_SUPPORT_DIR" ]; then
    rm -rf "$APP_SUPPORT_DIR"
    echo "已清除应用支持目录"
fi

# 清除钥匙串中与该应用相关的所有条目
echo "清除钥匙串中的旧数据..."
security delete-generic-password -s "$BUNDLE_ID" -a "bailianApiKey" 2>/dev/null || true
security delete-generic-password -s "$BUNDLE_ID" -a "aiApiKey" 2>/dev/null || true
security delete-generic-password -s "$BUNDLE_ID" -a "com.mouthtype.app" 2>/dev/null || true
echo "已清理钥匙串数据"

echo ""
echo "=== 构建 MouthType ==="
swift build -c release

echo "=== 创建应用 Bundle ==="
# 创建 app bundle 目录结构
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制二进制文件
cp "$BUILD_DIR/MouthType" "$APP_BUNDLE/Contents/MacOS/MouthType"
cp "$PROJECT_DIR/Sources/MouthType/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "=== 复制 Whisper Small 模型到应用 ==="
mkdir -p "$APP_MODEL_DIR"
if [ -f "$MODEL_DIR/ggml-small.bin" ]; then
    cp "$MODEL_DIR/ggml-small.bin" "$APP_MODEL_DIR/ggml-small.bin"
    echo "Whisper Small 模型已复制到应用 Bundle"
else
    echo "警告：未找到 Whisper Small 模型文件"
fi

echo "=== 复制 SenseVoice Small 模型到应用 ==="
SENSEVOICE_MODEL_DIR="$PROJECT_DIR/Resources/sensevoice-models"
APP_SENSEVOICE_MODEL_DIR="$APP_BUNDLE/Contents/Resources/sensevoice-models"
mkdir -p "$APP_SENSEVOICE_MODEL_DIR"
if [ -f "$SENSEVOICE_MODEL_DIR/sense-voice-small-q4_0.gguf" ]; then
    cp "$SENSEVOICE_MODEL_DIR/sense-voice-small-q4_0.gguf" "$APP_SENSEVOICE_MODEL_DIR/sense-voice-small-q4_0.gguf"
    echo "SenseVoice Small 模型已复制到应用 Bundle"
else
    echo "警告：未找到 SenseVoice Small 模型文件（可选）"
fi

echo "=== 签名 entitlements ==="
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "=== 验证签名 ==="
codesign --verify --display --entitlements - "$APP_BUNDLE"

echo "=== 完成 ==="
echo "应用位置：$APP_BUNDLE"
open "$APP_BUNDLE"
