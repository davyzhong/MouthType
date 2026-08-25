#!/usr/bin/env bash
# MouthType 权限授予脚本
# 用法：./scripts/grant-permissions.sh

set -euo pipefail

BUNDLE_ID="com.mouthtype.app"
APP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/debug-app/MouthType.app"

echo "==> MouthType 权限授予工具"
echo ""

# 检查应用是否存在
if [[ ! -d "$APP_PATH" ]]; then
    echo "错误：应用不存在 $APP_PATH"
    echo "请先运行：./scripts/build.sh"
    exit 1
fi

# 重置权限
echo "==> 重置权限..."
echo "需要输入管理员密码以重置 TCC 权限"
sudo tccutil reset Accessibility "$BUNDLE_ID"
sudo tccutil reset EventObservation "$BUNDLE_ID"
sudo tccutil reset AppleEvents "$BUNDLE_ID"

echo ""
echo "✓ 权限已重置"
echo ""

# 打开系统设置
echo "==> 请在系统设置中授予以下权限："
echo ""
echo "1. 辅助功能权限"
echo "   即将打开：系统设置 > 隐私与安全性 > 辅助功能"
echo ""
read -p "按回车键打开设置..."

# macOS 13+ 使用新的设置 URL
if [[ $(sw_vers -productVersion | cut -d. -f1) -ge 13 ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
else
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi

echo ""
echo "请在辅助功能列表中找到并勾选 'MouthType'"
echo ""
read -p "勾选后按回车键继续..."

echo ""
echo "2. 输入监控权限"
echo "   即将打开：系统设置 > 隐私与安全性 > 输入监控"
echo ""
read -p "按回车键打开设置..."

if [[ $(sw_vers -productVersion | cut -d. -f1) -ge 13 ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_EventObservation"
else
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_EventObservation"
fi

echo ""
echo "请在输入监控列表中找到并勾选 'MouthType'"
echo ""
read -p "勾选后按回车键继续..."

echo ""
echo "==> 权限授予完成！"
echo ""
echo "现在可以启动 MouthType 并测试热键功能了。"
echo "热键：右侧 Command ⌘"
