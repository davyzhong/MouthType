# MouthType — macOS Native Voice Dictation App Design Plan

## 当前实现快照（2026-04-02）

以下内容已经不是纯设计，而是当前工程实现与设计之间的对照结论：

### 已落地
- SwiftUI / AppKit 原生应用骨架
- 悬浮胶囊与菜单栏入口
- 权限展示、请求与系统设置跳转
- 可配置激活热键
- 本地 Whisper 点按式听写链路
- Bailian 流式 fallback
- Keychain 化 API key 存储路径

### 正在收口
- key-up 时 Bailian 流式尾音完整性
- `.error` 状态后的恢复能力
- 自动化测试与系统化验收

### 尚未完成
- 本地流式离线 ASR 完整接入
- AI 后处理 runtime 闭环
- Agent 指令模式
- ContextService / 自动术语学习
- 历史记录
- 模型下载管理器
- 麦克风设备管理
- 首启 onboarding

详细现状请参考：[当前项目现状](current-status.md)

## Context

Mouthpiece 是一个功能丰富的 Electron 语音听写应用，但存在以下问题：
- 支持 7 种 ASR + 5 种 AI provider + 3 个桌面平台，功能臃肿
- Electron 包体 ~200MB+，启动慢，IPC 开销大
- 大量平台分支代码（Windows/Linux），macOS 体验未充分优化
- 术语管理只有手动添加，中文场景下转写准确率受限

目标：基于 Mouthpiece 的经验，设计一个纯 macOS 原生 SwiftUI 语音听写应用，聚焦核心场景（听写 + 实时流式），面向国内用户，本地优先 + 百炼云端 fallback。

## Architecture Overview

```
SwiftUI Application (单进程)
├── UI Layer
│   ├── FloatingCapsule (NSPanel, 始终置顶, 透明背景)
│   ├── SettingsWindow (SwiftUI)
│   ├── HistoryWindow (SwiftUI + GRDB)
│   └── StatusItem (菜单栏)
├── Service Layer (async/await, protocol-based)
│   ├── ASRService (协议化, 可插拔 provider)
│   ├── AIService (协议化, 可插拔 provider)
│   ├── ClipboardService (粘贴)
│   └── ContextService (术语感知)
└── Platform Layer (macOS API 直接调用)
    ├── AudioCapture (AVAudioEngine)
    ├── HotkeyMonitor (IOKit / NSEvent)
    ├── AccessibilityBridge (AXUIElement)
    └── AppleScriptBridge (NSAppleScript)

External Processes (子进程):
  whisper-cpp-cli (本地非流式)
  sherpa-onnx-cli (本地流式)
```

## Module Design

### 1. ASR Engine Layer

**Protocol:**
```swift
protocol ASRProvider {
    func transcribe(audio: URL, options: ASROptions) async throws -> ASRResult
    func startStreaming(options: ASROptions) async throws -> AsyncThrowingStream<ASRSegment, Error>
    func stopStreaming() async
    var isAvailable: Bool { get async }
}
```

**Implementations:**
- `LocalWhisperProvider`: whisper-cpp-cli 子进程调用
  - Tap 模式: 写 WAV 临时文件 → Process 启动 → 解析 stdout → 删除临时文件
  - Hold 流式: sherpa-onnx-cli 子进程，stdin 管道写入 PCM chunks，stdout 逐行读取 JSON ASRSegment
- `BailianProvider`: 阿里云百炼
  - 当前 P0 主链路只使用 WebSocket Paraformer 流式 fallback
  - 非流式 `chat/completions` 封装目前仍保留在代码中，但未接入当前 hotkey runtime 主链路

**引擎选择策略（当前 P0 实现）:**
- 按下热键后优先走本地录音 + `LocalWhisperProvider.transcribe()`
- 仅当本地引擎“完全不可用”时，才切到 `BailianStreamingProvider.startStreaming()`
- 本地流式离线 ASR（如 sherpa-onnx / Parakeet）仍属于后续阶段目标，尚未进入当前运行时主链路

**模型存储:**
- `~/Library/Application Support/MouthType/Models/whisper/` — ggml-base.bin 等
- `~/Library/Application Support/MouthType/Models/parakeet/` — parakeet-tdt-0.6b-v3/

### 2. AI Post-Processing Layer

**Protocol:**
```swift
protocol AIProvider {
    func process(text: String, instruction: AIInstruction) async throws -> AIResult
    var isAvailable: Bool { get async }
}
```

**Implementations:**
- `BailianAIProvider`: 百炼通义 (DashScope 兼容接口, 支持 thinking 模式)
- `LocalLLMProvider`: llama.cpp CLI 子进程 (GGUF 模型)
- 扩展 slot: protocol 设计支持后续加 DeepSeek、GLM 等

**AIMode:**
- `.cleanup`: 基础文本清理 (去语气词、标点修正)
- `.rewrite`: 风格改写
- `.agentCommand`: "Hey [AgentName]" 指令模式

### 3. Platform Bridge Layer (macOS Only)

**HotkeyMonitor:**
- IOKit HID 或 NSEvent.addGlobalMonitorForEvents
- 默认热键: Fn 键
- 回调: onTap (< 300ms) / onHoldStart / onHoldStop
- 进程内监听，无需独立 Swift 二进制（对比 Mouthpiece 的 globe-listener.swift）

**AudioCapture:**
- AVAudioEngine 直接录音
- Tap 模式: 输出 PCM → WAV 临时文件
- Hold 模式: 输出 PCM chunks → 管道
- onAudioLevel 回调驱动 UI 波形动画
- 对比 Mouthpiece: 砍掉 MediaRecorder → Blob → IPC → File 整条链路

**PasteService:**
- NSAppleScript: `tell application "System Events" to keystroke "v" using command down`
- 终端检测: Cmd+Shift+V
- 需要辅助功能权限（首次启动引导）
- 对比 Mouthpiece: 无需 macos-fast-paste.swift 独立二进制

**ContextService (核心升级):**
- AXUIElement API 读取前台应用 focused element 的文本内容
- NLP 分词 + 频率分析提取专有名词
- 和自定义术语库去重合并
- 作为 hotwords 传给 ASR provider
- 需要辅助功能权限（和粘贴共享同一权限）
- 对比 Mouthpiece: 从手动词典升级为自动上下文感知学习

### 4. UI Layer

**FloatingCapsule (NSPanel):**
- NSFloatingWindowLevel, 透明背景, 无边框
- 始终置顶, 不抢焦点 (canBecomeKeyWindow = false)
- 可拖拽
- 显示: 状态指示 + 波形动画 + 实时流式文字预览 (Hold 模式)

**SettingsWindow:**
- 通用: 热键、语言、主题
- ASR: 引擎选择、模型管理/下载
- AI: Provider、API Key、后处理风格、Agent 名称
- 术语: 自定义词典、自动学习开关
- 麦克风: 设备选择、音量测试

**HistoryWindow:**
- 转写历史列表 (SQLite/GRDB)
- 搜索、删除、复制、重新 AI 处理

**StatusItem (菜单栏):**
- 显示/隐藏悬浮胶囊
- 打开设置、历史
- 引擎状态指示
- 退出

### 5. State Machine

```swift
enum DictationState {
    case idle                    // 待机
    case recording               // 本地录音中
    case streaming(String)       // Bailian fallback 流式转写中
    case processing              // 本地 tap 转写处理中
    case aiProcessing            // AI 后处理中
    case error(String)           // 错误
}

idle → recording (热键按下，默认本地录音)
recording → processing (松开热键后进入本地转写)
recording → streaming (仅当本地引擎不可用时，进入 Bailian fallback)
streaming → idle (松开后收尾并粘贴结果)
processing → aiProcessing (启用 AI 时)
processing → idle (无 AI, 直接粘贴)
aiProcessing → idle (AI 完成, 粘贴)
```

### 6. Data & Storage

| 存储 | 用途 | 技术 |
|------|------|------|
| UserDefaults | 轻量设置 | Foundation |
| Keychain | API Keys | Security.framework |
| SQLite | 转写历史、术语库 | GRDB.swift |

**文件结构:**
```
~/Library/Application Support/MouthType/
  ├── Models/whisper/     ← ggml models
  ├── Models/parakeet/    ← sherpa-onnx models
  ├── Database.sqlite     ← GRDB
  └── Settings/           ← 导出/备份
```

### 7. AppSettings 结构

```swift
struct AppSettings {
    // ASR
    var asrProvider: ASRProviderType       // .localWhisper | .localParakeet | .bailian
    var whisperModel: String
    var parakeetModel: String
    var preferredLanguage: String
    var asrFallbackEnabled: Bool

    // AI
    var aiEnabled: Bool
    var aiProvider: AIProviderType
    var aiMode: AIMode
    var agentName: String

    // 术语
    var contextLearningEnabled: Bool
    var customTerms: [String]

    // 交互
    var hotkey: String
    var holdThreshold: TimeInterval        // 300ms
    var audioCuesEnabled: Bool

    // 麦克风
    var preferredMicDeviceId: String?
}
```

## What We Cut vs Mouthpiece

| Mouthpiece Feature | MouthType | Reason |
|---|---|---|
| 7 ASR providers | 2 (本地 + 百炼) | 国内可用，减少维护 |
| 5 AI providers | 2+ (百炼 + 本地, protocol 可扩展) | 国内可用 |
| Windows/Linux 平台 | macOS only | 聚焦单平台 |
| OAuth/用户系统 | 无 | 纯本地工具 |
| Electron + React | SwiftUI | 原生性能 |
| 手动词典 | 自动上下文学习 | 核心升级 |
| globe-listener.swift 独立二进制 | 进程内 IOKit | 简化部署 |
| MediaRecorder → IPC 链路 | AVAudioEngine 直录 | 零延迟 |
| 推荐系统 | 无 | 不需要 |

## MVP Implementation Phases

### Phase 1: Skeleton (最小可运行)
- Xcode 项目创建, SwiftUI App 结构
- NSPanel 悬浮窗口 (空白)
- 菜单栏 StatusItem
- AVAudioEngine 录音到文件
- whisper-cpp-cli 子进程调用 (Tap 模式)
- AppleScript 粘贴
- UserDefaults 基础设置

### Phase 2: Hold Streaming + Fallback
- HotkeyMonitor (Fn 键, tap/hold 判定)
- sherpa-onnx-cli 子进程流式调用
- 悬浮胶囊显示流式文字
- 百炼 WebSocket 流式 fallback
- ASR provider 协议 + 切换逻辑

### Phase 3: AI + Context
- BailianAIProvider (百炼通义)
- Agent 指令检测 ("Hey X")
- ContextService (AXUIElement 上下文提取)
- 术语自动学习 + 手动管理
- AI 后处理 UI 开关

### Phase 4: Polish
- GRDB 历史记录
- 设置面板完善
- 模型下载管理器 (带进度)
- 首次启动引导 (权限 + 模型下载)
- 音频提示音
- 拖拽悬浮胶囊

## Key Dependencies (Swift Package Manager)

- **GRDB.swift**: SQLite ORM
- **Whisper.cpp**: CLI binary (预编译, bundled in app)
- **sherpa-onnx**: CLI binary (预编译, bundled in app)
- 无其他第三方依赖 (AVAudioEngine, AXUIElement, NSAppleScript, Keychain 全部系统框架)

## Verification Plan

1. **Phase 1 验证**: 启动应用 → 看到 NSPanel → 按激活热键录音 → 松开后本地 Whisper 转写 → 文本粘贴到 Notes.app
2. **Phase 2 验证**: 在本地引擎不可用前提下按住热键 → 进入 Bailian 流式 fallback → 松开后完成收尾并粘贴 → 验证不会自动上传本地运行期失败音频
3. **Phase 3 验证**: 在 TextEdit 中打开含专有名词的文档 → 按热键说出这些名词 → 验证后续 ContextService 接入后的转写准确率提升
4. **Phase 4 验证**: 首次启动引导流程完整走通 → 模型下载有进度 → 历史记录可搜索
