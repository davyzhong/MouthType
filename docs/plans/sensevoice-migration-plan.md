# SenseVoice Small 迁移计划

## 概述

将默认离线转录引擎从 Whisper Small 迁移到 SenseVoice Small，需要进行全面的代码修改。本文档详述所有需要修改的文件和细节。

---

## SenseVoice 模型版本对比

### 可选版本

| 版本 | 格式 | 大小 | 特点 | 下载源 |
|------|------|------|------|--------|
| **SenseVoice Small (GGML)** | GGML | ~300-500MB | CPU 推理，SenseVoice.cpp 项目 | [GitHub](https://github.com/lovemefan/SenseVoice.cpp/releases) / [ModelScope](https://www.modelscope.cn/models/lovemefan/SenseVoiceGGUF) |
| **SenseVoice Small (ONNX)** | ONNX | ~400MB | 支持 GPU 加速，sherpa-onnx 项目 | [ModelScope](https://www.modelscope.cn/models/poloniumrock/SenseVoiceSmallOnnx) / [GitHub](https://github.com/k2-fsa/sherpa-onnx/releases) |

### 推荐方案

**推荐 GGML 版本**，原因：
1. 架构与 Whisper.cpp 类似，可以复用 WhisperProvider 的子进程调用模式
2. CPU 推理，无需 GPU 依赖
3. 官方支持多语言（中文、英语、日语、韩语）
4. 情感识别能力（可选功能）

---

## 修改清单

### 1. 数据模型层

#### 1.1 `ASRProvider.swift`

**修改内容：**
- 添加 `.localSenseVoice` 到 `ASRProviderType` 枚举

```swift
enum ASRProviderType: String, CaseIterable, Sendable {
    case localWhisper = "Local Whisper (whisper.cpp)"
    case localSenseVoice = "Local SenseVoice (sensevoice.cpp)"  // 新增
    case localParakeet = "Local Parakeet (sherpa-onnx)"
    case bailianStreaming = "Aliyun Bailian Streaming (Cloud)"
    case bailian = "Aliyun Bailian (Cloud)"

    var displayName: String {
        switch self {
        case .localWhisper: "本地 Whisper (whisper.cpp)"
        case .localSenseVoice: "本地 SenseVoice (中文推荐)"  // 新增
        case .localParakeet: "本地 Parakeet (sherpa-onnx)"
        case .bailianStreaming: "百炼流式 (云端，中文推荐)"
        case .bailian: "百炼云端 (回退)"
        }
    }
}
```

**影响范围：**
- 所有使用 `ASRProviderType.allCases` 的 UI Picker
- 所有 switch 语句处理 `asrProvider` 的地方

---

### 2. 服务层

#### 2.1 新建 `SenseVoiceProvider.swift`

**文件位置：** `Sources/MouthType/Services/SenseVoiceProvider.swift`

**职责：**
- 实现 `ASRProvider` 协议
- 调用 `sensevoice-cli` 二进制文件
- 处理 GGML 模型文件

**参考实现：** 基于 `WhisperProvider.swift` 修改

```swift
import Foundation
import os

private let senseVoiceLog = Logger(subsystem: "com.mouthtype", category: "SenseVoiceProvider")

final class SenseVoiceProvider: ASRProvider {
    private let settings = AppSettings.shared

    var availabilityError: SenseVoiceError? {
        let modelURL = settings.senseVoiceModelURL
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return .modelNotFound(modelURL.path)
        }

        do {
            _ = try findSenseVoiceBinary()
            return nil
        } catch let error as SenseVoiceError {
            return error
        } catch {
            return .binaryNotFound
        }
    }

    var isAvailable: Bool {
        availabilityError == nil
    }

    func transcribe(audioURL: URL, hotwords: [String] = []) async throws -> ASRResult {
        // 类似 WhisperProvider 的实现
        // 注意：SenseVoice 的 CLI 参数可能不同
    }

    func startStreaming(hotwords: [String]) async throws -> AsyncThrowingStream<ASRSegment, Error> {
        // 可能不支持流式，抛出错误
        throw SenseVoiceError.streamingNotSupported
    }

    func stopStreaming() async {}
    func sendAudio(_ pcmData: Data) async {}

    // MARK: - Private

    private func findSenseVoiceBinary() throws -> URL {
        // 查找 sensevoice-cli 二进制
        let candidates = [
            "/opt/homebrew/bin/sensevoice-cli",
            "/usr/local/bin/sensevoice-cli",
            Bundle.main.resourceURL?.appendingPathComponent("bin/sensevoice-cli").path,
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        throw SenseVoiceError.binaryNotFound
    }

    private func parseTranscription(_ output: String) -> String {
        // 解析 SenseVoice 输出格式
    }
}

enum SenseVoiceError: LocalizedError {
    case audioFileNotFound
    case modelNotFound(String)
    case binaryNotFound
    case processFailed(String)
    case streamingNotSupported

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound: "未找到音频文件"
        case .modelNotFound(let path): "未找到 SenseVoice 模型：\(path)"
        case .binaryNotFound: "未找到 sensevoice-cli 可执行文件"
        case .processFailed(let msg): "SenseVoice 进程执行失败：\(msg)"
        case .streamingNotSupported: "SenseVoice 不支持流式转写"
        }
    }
}
```

---

#### 2.2 修改 `AppSettings.swift`

**修改内容：**

1. 添加 `senseVoiceModel` 属性
2. 添加 `senseVoiceModelURL` 计算属性

```swift
// 在 whisperModel 后添加：
var senseVoiceModel: String {
    get { defaults.string(forKey: "senseVoiceModel") ?? "small" }
    set { defaults.set(newValue, forKey: "senseVoiceModel") }
}

var senseVoiceModelURL: URL {
    let bundleModelURL = Bundle.main.url(
        forResource: "sensevoice-models/ggml-\(senseVoiceModel)",
        withExtension: "bin"
    )
    if let url = bundleModelURL, FileManager.default.fileExists(atPath: url.path) {
        return url
    }
    return modelsDirectory.appendingPathComponent("sensevoice/ggml-\(senseVoiceModel).bin")
}
```

---

#### 2.3 修改 `ModelManager.swift`

**修改内容：**

1. 添加 `SenseVoiceModel` 结构体（或复用 `WhisperModel`）
2. 添加 `availableSenseVoiceModels` 数组
3. 添加下载和管理方法

```swift
// MARK: - SenseVoice Models

struct SenseVoiceModel: Identifiable, Hashable {
    let name: String
    let filename: String
    let sizeLabel: String
    let url: URL

    var id: String { filename }
}

let availableSenseVoiceModels: [SenseVoiceModel] = [
    SenseVoiceModel(
        name: "Small (中文推荐)",
        filename: "ggml-small.bin",
        sizeLabel: "~400 MB",
        url: URL(string: "https://hf-mirror.com/lovemefan/SenseVoiceGGUF/resolve/main/ggml-small.bin")!
    ),
    // 可根据需要添加更多版本
]

func senseVoiceModelURL(for model: SenseVoiceModel) -> URL {
    settings.modelsDirectory.appendingPathComponent("sensevoice/\(model.filename)")
}

func isSenseVoiceModelDownloaded(_ model: SenseVoiceModel) -> Bool {
    FileManager.default.fileExists(atPath: senseVoiceModelURL(for: model).path)
}

@MainActor
func download(model: SenseVoiceModel, progress: @escaping (Double) -> Void) async throws {
    // 类似 Whisper 下载逻辑
}

func deleteSenseVoiceModel(_ model: SenseVoiceModel) throws {
    let url = senseVoiceModelURL(for: model)
    if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
    }
}
```

---

### 3. 平台层

#### 3.1 修改 `HotkeyMonitor.swift`

**修改内容：**

1. 添加 `senseVoiceProvider` 属性
2. 在 `startDictation()` 的 switch 中添加 `.localSenseVoice` 分支
3. 添加 `startSenseVoiceTapMode()` 方法

```swift
// 添加属性
private let senseVoiceProvider = SenseVoiceProvider()

// 修改 startDictation()
switch settings.asrProvider {
case .localWhisper:
    startWhisperTapMode()
case .localSenseVoice:  // 新增
    startSenseVoiceTapMode()
case .localParakeet:
    startLocalStreamingMode()
case .bailianStreaming, .bailian:
    startCloudFallbackMode()
}

// 添加方法
private func startSenseVoiceTapMode() {
    if let availabilityError = senseVoiceProvider.availabilityError {
        if startCloudFallbackIfNeeded(availabilityError) { return }
        appState.transition(to: .error(availabilityError.localizedDescription))
        return
    }

    do {
        let url = try audioCapture.startRecording()
        tapRecordingURL = url
        appState.transition(to: .recording)
        hotkeyLog.info("Recording started (SenseVoice tap mode)")
    } catch {
        appState.transition(to: .error("麦克风错误：\(error.localizedDescription)"))
    }
}

// 修改 hotkey 释放处理
private func releaseHotkeyAndPaste() async throws {
    // ...
    switch settings.asrProvider {
    case .localWhisper:
        result = try await whisperProvider.transcribe(audioURL: audioURL)
    case .localSenseVoice:  // 新增
        result = try await senseVoiceProvider.transcribe(audioURL: audioURL)
    // ...
    }
}
```

---

### 4. UI 层

#### 4.1 修改 `SettingsView.swift`

**修改内容：**

1. 添加 `senseVoiceModel` 的 `@AppStorage`
2. 在 ASR Provider Picker 中显示 SenseVoice 选项
3. 添加 SenseVoice 模型选择 UI

```swift
// 添加属性
@AppStorage("senseVoiceModel") private var senseVoiceModel: String = "small"

// 修改 ASR Provider Section
Section("引擎") {
    Picker("ASR 提供商", selection: $asrProviderRawValue) {
        ForEach(ASRProviderType.allCases, id: \.rawValue) { provider in
            Text(provider.displayName).tag(provider.rawValue)
        }
    }
    
    // 修改提示文本
    Text("中文场景推荐使用「百炼流式」或「SenseVoice」，识别率最高。离线环境使用本地引擎。")
        .font(.caption)
        .foregroundStyle(.secondary)

    if asrProvider == .localWhisper {
        // ... 现有 Whisper 模型选择
    }
    
    // 新增 SenseVoice 模型选择
    if asrProvider == .localSenseVoice {
        Picker("SenseVoice 模型", selection: $senseVoiceModel) {
            Text("Small (中文推荐，约 400MB)").tag("small")
        }
        Text("SenseVoice 针对中文优化，速度快于 Whisper。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

---

#### 4.2 修改 `ModelManagerView.swift`

**修改内容：**

1. 添加 SenseVoice 模型列表 Section
2. 添加下载状态管理

```swift
var body: some View {
    Form {
        // 现有 Whisper Section
        Section("Whisper 模型") {
            // ...
        }
        
        // 新增 SenseVoice Section
        Section("SenseVoice 模型") {
            ForEach(manager.availableSenseVoiceModels) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(model.name)
                                .font(.system(size: 13, weight: .medium))
                            Text("中文推荐")
                                .font(.caption)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(3)
                        }
                        Text(model.sizeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // 下载/使用/删除按钮逻辑（同 Whisper）
                }
            }
        }
        
        // 现有配置 Section
        Section("当前配置") {
            // ...
        }
    }
}
```

---

#### 4.3 修改 `OnboardingView.swift`

**修改内容：**

1. 更新 `ASREngineStepView` 中的模型选择

```swift
struct ASREngineStepView: View {
    @Binding var asrProvider: String
    @State private var whisperModel: String = "base"
    @State private var senseVoiceModel: String = "small"  // 新增

    var body: some View {
        // ...
        
        if selectedProvider == .localWhisper {
            // 现有 Whisper 模型选择
        }
        
        // 新增 SenseVoice 模型选择
        if selectedProvider == .localSenseVoice {
            VStack(alignment: .leading, spacing: 8) {
                Text("SenseVoice 模型选择")
                    .font(.headline)
                Picker("模型", selection: $senseVoiceModel) {
                    Text("Small (中文推荐，~400MB)").tag("small")
                }
                .pickerStyle(.radioGroup)
                
                Text("模型文件将在首次使用时自动下载")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
```

---

#### 4.4 修改 `About` 页面

**修改位置：** `SettingsView.swift` 底部的 About Tab

```swift
HStack {
    Text("本地语音识别")
    Spacer()
    Text("whisper.cpp / sensevoice.cpp（点按模式）")
        .foregroundStyle(.secondary)
}
```

---

### 5. 构建脚本

#### 5.1 修改 `build-with-entitlements.sh`

**修改内容：**

添加 SenseVoice 模型复制到 Bundle

```bash
# 在现有 Whisper 模型复制后添加
MODEL_DIR="$PROJECT_DIR/Resources/whisper-models"
APP_MODEL_DIR="$APP_BUNDLE/Contents/Resources/whisper-models"

if [ -f "$MODEL_DIR/ggml-small.bin" ]; then
    cp "$MODEL_DIR/ggml-small.bin" "$APP_MODEL_DIR/ggml-small.bin"
fi

# 新增：复制 SenseVoice 模型
SENSEVOICE_MODEL_DIR="$PROJECT_DIR/Resources/sensevoice-models"
APP_SENSEVOICE_MODEL_DIR="$APP_BUNDLE/Contents/Resources/sensevoice-models"

if [ -f "$SENSEVOICE_MODEL_DIR/ggml-small.bin" ]; then
    mkdir -p "$APP_SENSEVOICE_MODEL_DIR"
    cp "$SENSEVOICE_MODEL_DIR/ggml-small.bin" "$APP_SENSEVOICE_MODEL_DIR/ggml-small.bin"
fi
```

---

### 6. 文档

#### 6.1 修改 `CLAUDE.md`

**修改内容：**

更新项目概述，添加 SenseVoice 说明

```markdown
### 语音处理：whisper.cpp + NVIDIA Parakeet (via sherpa-onnx) + SenseVoice.cpp + OpenAI API
```

---

## 测试清单

### 单元测试
- [ ] `SenseVoiceProvider` 可用性检测
- [ ] `SenseVoiceProvider.transcribe()` 正常返回
- [ ] 模型文件缺失时正确报错
- [ ] 二进制缺失时正确报错

### 集成测试
- [ ] 在 Settings 中切换到 SenseVoice
- [ ] 下载 SenseVoice Small 模型
- [ ] 使用快捷键触发 SenseVoice 转写
- [ ] 验证转写结果为简体中文
- [ ] 验证历史纪录保存
- [ ] 验证 AI 后处理正常工作

### UI 测试
- [ ] Settings → ASR Provider Picker 显示 SenseVoice 选项
- [ ] Settings → SenseVoice 模型选择显示正常
- [ ] ModelManagerView → SenseVoice 模型列表显示正常
- [ ] OnboardingView → ASR 引擎选择显示 SenseVoice
- [ ] 所有文本均为简体中文

---

## 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| SenseVoice.cpp 二进制获取困难 | 提供 Homebrew 安装说明，或预打包二进制 |
| 模型下载 URL 不稳定 | 使用 hf-mirror.com 镜像，或考虑 bundled 模型 |
| CLI 参数与 Whisper 不同 | 详细阅读 SenseVoice.cpp 文档，调整参数解析 |
| 输出格式不同 | 调整 `parseTranscription()` 方法 |
| 不支持流式转写 | 保持 tap mode 设计，用户无感知 |

---

## 实施顺序

1. **Phase 1: 核心功能**
   - [ ] 创建 `SenseVoiceProvider.swift`
   - [ ] 修改 `ASRProviderType` 枚举
   - [ ] 修改 `HotkeyMonitor.swift` 添加支持

2. **Phase 2: 模型管理**
   - [ ] 修改 `AppSettings.swift` 添加配置
   - [ ] 修改 `ModelManager.swift` 添加模型定义
   - [ ] 修改 `ModelManagerView.swift` 添加 UI

3. **Phase 3: 设置界面**
   - [ ] 修改 `SettingsView.swift` 添加选项
   - [ ] 修改 `OnboardingView.swift` 添加选项

4. **Phase 4: 构建与分发**
   - [ ] 修改构建脚本
   - [ ] 测试模型打包

5. **Phase 5: 测试与验证**
   - [ ] 执行测试清单
   - [ ] 修复发现的问题

---

## 备注

- SenseVoice 的优势：针对中文优化，速度比 Whisper Small 快约 5 倍
- SenseVoice 的劣势：社区生态较小，更新频率可能不如 Whisper
- 建议保留 Whisper 作为备选，让用户自行选择
