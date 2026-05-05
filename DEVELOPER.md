# MouthType 开发者文档

## 项目概述

MouthType 是一款原生 macOS 语音转写应用，使用 Swift 和 SwiftUI 构建。支持本地 whisper.cpp 和云端 Bailian/Aliyun 等多种 ASR 提供商。

## 快速开始

### 环境要求

- macOS 14 (Sonoma) 或更高版本
- Xcode 15 或更高版本
- Swift 5.9+

### 构建

```bash
# Debug 构建
swift build

# 运行测试
swift test

# 带覆盖率测试
swift test --enable-code-coverage

# Release 构建
swift build -c release

# 使用统一构建脚本
./scripts/build.sh debug
./scripts/build.sh release
```

### 代码签名

```bash
# Ad-hoc 签名（开发）
codesign --force --deep --sign - .build/debug/MouthType

# 使用构建脚本自动签名
./scripts/build.sh release --sign
```

## 项目结构

```
Sources/MouthType/
├── Services/          # 核心服务（ASR、音频、VAD、日志脱敏）
├── UI/               # SwiftUI 视图
├── Platform/         # 平台相关（热键、权限、音频采集）
├── Models/           # 数据模型（AppState、AppSettings）
└── Utilities/        # 工具类

Tests/MouthTypeTests/  # 测试套件
preload/               # WebView 桥接模块
├── utils.js          # IPC 工具工厂
├── keys.js           # API Key 管理
├── streaming.js      # 流式 ASR
├── models.js         # 模型管理
├── window.js         # 窗口控制
├── database.js       # 数据库
└── system.js         # 系统服务
```

## 架构决策

### 双 UI 架构
- **浮动胶囊**：最小化覆盖层，始终置顶，可拖拽
- **设置面板**：WebKit WebView 设置界面
- **通信**：通过 preload.js 桥接

### 音频流水线
1. 用户按下热键 → AudioManager 开始录音
2. AVAudioEngine 收集音频缓冲
3. VADProcessor 分析语音活动
4. 音频发送到活跃 ASR 提供商
5. 结果通过回调返回
6. TextInsertionService 插入文本到活跃应用

### 安全策略
- API Key 存储在 Keychain，永不暴露给 WebView
- 云 API 调用通过主进程代理
- 日志自动脱敏敏感数据
- 敏感应用策略控制隐私级别

## 测试

### 测试结构
- 149 个测试，覆盖 6 个测试文件
- 新增：AudioPreprocessorTests、ChineseConverterTests、ProcessResultTests、ASRProviderTests、PerformanceBenchmarkTests

### 性能基准
```bash
swift test --filter PerformanceBenchmarkTests
```

当前基准：
- 音频预处理（100ms 缓冲）：~0.0003s
- 日志脱敏（短文本）：~0.0004s
- 中文转换（100 字符）：~0.0015s
- 转写稳定器追加：~0.0003s

### 代码覆盖率
```bash
swift test --enable-code-coverage
xcrun llvm-cov report --use-color=true \
  .build/arm64-apple-macosx/debug/MouthTypePackageTests.xctest/Contents/MacOS/MouthTypePackageTests \
  --instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata
```

当前覆盖率：~10.76%（行），主要覆盖 Models 和部分 Services。

## CI/CD

GitHub Actions 工作流 `.github/workflows/ci.yml`：
- macOS 14 runner
- Debug/Release 构建
- 测试套件
- SwiftLint（可选）
- 代码覆盖率报告

## 开发指南

### 添加新 IPC 通道
1. 在 `preload.js` 中注册通道
2. 在对应的 Swift 处理类中实现 handler
3. 在 `preload/` 子模块中暴露 API

### 添加新设置
1. 更新 `AppSettings.swift`
2. 更新 `SettingsView.swift`
3. 如有敏感数据，使用 Keychain

### 添加新测试
1. 在 `Tests/MouthTypeTests/` 创建测试文件
2. 继承 `XCTestCase`
3. 使用 `@testable import MouthType`

## 常见问题

### 无音频检测
- 检查系统设置中的麦克风权限
- 验证音频输入设备选择
- 检查调试日志中的音频级别

### 转写失败
- 确认 whisper.cpp 二进制文件可用
- 验证模型已下载
- 检查云提供商的 API Key 配置

### 文本插入不工作
- macOS：检查辅助功能权限
- 验证目标应用允许文本输入
- 检查应用是否在阻止列表中

## 贡献

提交信息格式：
```
fix: 修复登录页面的样式问题 / Fix login page styling issue

Changes:
- Adjusted button padding on mobile devices
- Fixed color contrast for accessibility
- Updated error message positioning
```

## 许可证

[待补充]
