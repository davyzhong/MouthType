#!/usr/bin/env bash
# 下载并安装 whisper-cli 到 App Bundle
# 适用于 macOS ARM64

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/debug-app/MouthType.app"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
BIN_DIR="$RESOURCES_DIR/bin"

echo "==> 安装 whisper-cli 到 App Bundle"

# 创建 bin 目录
mkdir -p "$BIN_DIR"

# 检查是否有 brew 安装的 whisper-cli
if command -v whisper-cli &> /dev/null; then
    echo "✓ 发现 brew 安装的 whisper-cli"
    cp "$(which whisper-cli)" "$BIN_DIR/"
    chmod +x "$BIN_DIR/whisper-cli"
    echo "✓ 已复制到 $BIN_DIR/whisper-cli"
    exit 0
fi

# 下载预编译的 whisper-cli
echo "==> 下载 whisper-cli..."
PLATFORM="macos-arm64"  # 假设是 Apple Silicon
WHISPER_VERSION="1.7.2"

# GitHub release 下载
DOWNLOAD_URL="https://github.com/ggerganov/whisper.cpp/releases/download/v${WHISPER_VERSION}/whisper-bin-${PLATFORM}.zip"
TEMP_DIR=$(mktemp -d)

echo "下载：$DOWNLOAD_URL"
curl -L -o "$TEMP_DIR/whisper.zip" "$DOWNLOAD_URL"

# 解压
unzip -o "$TEMP_DIR/whisper.zip" -d "$TEMP_DIR"

# 查找 whisper-cli (可能是 whisper-main 或 whisper-cli)
if [[ -f "$TEMP_DIR/whisper-cli" ]]; then
    cp "$TEMP_DIR/whisper-cli" "$BIN_DIR/"
elif [[ -f "$TEMP_DIR/whisper-main" ]]; then
    cp "$TEMP_DIR/whisper-main" "$BIN_DIR/whisper-cli"
elif [[ -f "$TEMP_DIR/whisper-bin-arm/whisper-cli" ]]; then
    cp "$TEMP_DIR/whisper-bin-arm/whisper-cli" "$BIN_DIR/"
else
    echo "未找到 whisper-cli 二进制"
    ls -la "$TEMP_DIR/"
    exit 1
fi

chmod +x "$BIN_DIR/whisper-cli"

# 清理
rm -rf "$TEMP_DIR"

echo "✓ 已安装到 $BIN_DIR/whisper-cli"
echo ""
echo "==> 重新签名 App Bundle"
codesign --force --deep --sign - --entitlements "$ROOT_DIR/Sources/MouthType/MouthType.entitlements" "$APP_BUNDLE"

echo ""
echo "✓ 完成！请重启 MouthType 应用"
