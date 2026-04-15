# FunASR Paraformer 集成计划

**创建日期：** 2026-04-02  
**状态：** 实施中  
**优先级：** 高

---

## 执行摘要

经过调研，**FunASR Paraformer 是中文语音识别的最佳选择**，在中文场景下识别准确率 (CER 3.05-4.8%) 优于 Whisper (CER 8%+) 和 SenseVoice (CER 5.4%)。

### 推荐方案：Sherpa-ONNX + Paraformer ONNX 模型

| 对比项 | Whisper.cpp | SenseVoice.cpp | Paraformer (ONNX) |
|--------|-------------|----------------|-------------------|
| 中文识别准确率 | ~8% CER | ~5.4% CER | **~3-4.8% CER** ✅ |
| 推理速度 | 基准 | 快 2-3 倍 | 快 2-3 倍 ✅ |
| 模型格式 | GGUF ✅ | GGUF ✅ | **ONNX** ⚠️ |
| C++ 实现 | 成熟 ✅ | 成熟 ✅ | **需 ONNX Runtime** ⚠️ |
| macOS/Swift 集成 | 成熟 ✅ | 成熟 ✅ | **需 ONNX Runtime** ⚠️ |
| 模型大小 | 75MB-3GB | ~182MB | **79-234MB (INT8)** ✅ |

---

## 技术方案对比

### 方案 A：Sherpa-ONNX + Paraformer（推荐）

**优势：**
- Sherpa-ONNX 已集成 Paraformer 模型
- 提供现成的 ONNX 模型 (INT8 量化后 79-234MB)
- 支持 C++ API，可封装为 Swift 调用
- 跨平台支持 (macOS/iOS/Linux/Windows)

**劣势：**
- 需要集成 ONNX Runtime
- 模型格式为 ONNX，非 GGUF (不能复用 whisper.cpp 架构)

**模型下载：**
```bash
# sherpa-onnx Paraformer 中文模型
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-int8-2025-10-07.tar.bz2
```

### 方案 B：FunASR 官方 iOS/macOS SDK

**优势：**
- 官方支持，文档完整
- 提供 CocoaPods 集成 (`pod install`)
- 支持 Objective-C/Swift 调用

**劣势：**
- 有用户报告在 macOS 14.2 + Xcode 15.1 + M2 上存在编译问题 ([Issue #2280](https://github.com/modelscope/FunASR/issues/2280))
- SDK 体积较大
- 依赖阿里生态

**集成方式：**
```ruby
# Podfile
pod 'FunASR'
```

### 方案 C：paraformer.cpp (GGML/GGUF)

**状态：** 开发中，**不成熟** ⚠️

- GitHub: [lovemefan/paraformer.cpp](https://github.com/lovemefan/paraformer.cpp)
- 无预编译模型，需自行转换
- 无 releases
- 文档不完整

**不推荐用于生产环境**

---

## 实施计划

### 阶段一：技术验证（1-2 天）

1. **下载并测试 sherpa-onnx Paraformer 模型**
   ```bash
   wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-int8-2025-10-07.tar.bz2
   tar xvf sherpa-onnx-paraformer-zh-int8-2025-10-07.tar.bz2
   # 测试命令行转写
   ./build/bin/sherpa-onnx-offline --model=... --audio=...
   ```

2. **验证识别效果**
   - 准备中文测试音频
   - 对比 Whisper/SenseVoice/Paraformer 的识别结果
   - 确认准确率提升

### 阶段二：集成开发（3-5 天）

1. **集成 ONNX Runtime**
   - 使用 `onnxruntime-swift` 或封装 C API
   - 或集成 sherpa-onnx 的 C/C++ 库

2. **创建 ASRProvider 实现**
   - 类似 WhisperProvider 架构
   - 支持热词、语言选择
   - 实现 `transcribe()` 方法

3. **UI 适配**
   - SettingsView 添加 Paraformer 选项
   - ModelManagerView 支持模型下载管理
   - 移除或降级 SenseVoice 为备选

### 阶段三：优化与测试（2-3 天）

1. **性能优化**
   - CPU/GPU 推理优化
   - 内存占用优化
   - 模型量化验证

2. **全面测试**
   - 中文普通话识别
   - 方言识别
   - 嘈杂环境测试
   - 长音频测试

---

## 风险与挑战

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| paraformer.cpp 不成熟 | 高 | 使用 sherpa-onnx 方案 |
| ONNX Runtime 集成复杂度 | 中 | 使用成熟 Swift 封装库 |
| 模型体积较大 | 低 | 使用 INT8 量化版本 (79MB) |
| 流式识别支持 | 中 | 初期使用离线模式，后续扩展 |

---

## 代码架构建议

```swift
// 新增 ParaformerProvider.swift
final class ParaformerProvider: ASRProvider {
    private let modelURL: URL
    private let onnxSession: ORTSession
    
    func transcribe(audioURL: URL, hotwords: [String]) async throws -> ASRResult
}

// 扩展 ASRProviderType 枚举
enum ASRProviderType: String, CaseIterable {
    case localWhisper = "Local Whisper (whisper.cpp)"
    case localSenseVoice = "Local SenseVoice (sensevoice.cpp)"
    case localParaformer = "Local Paraformer (ONNX)"  // 新增
    case bailianStreaming = "Aliyun Bailian Streaming (Cloud)"
}
```

---

## 最终建议

**立即执行：**
1. ✅ 采用 **sherpa-onnx + Paraformer ONNX** 方案
2. ✅ 保留 SenseVoice 作为备选（已实现，可正常工作）
3. ✅ 移除对 sensevoice-cli 的依赖（编译问题无法解决）

**后续优化：**
1. 根据实际测试结果调整默认引擎
2. 如 Paraformer 效果显著优于 SenseVoice，可设为默认中文引擎
3. 保持 Whisper 作为多语言场景选项

---

## 参考资料

- [sherpa-onnx Paraformer 模型](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-paraformer/paraformer-models.html)
- [FunASR GitHub](https://github.com/modelscope/FunASR)
- [lovemefan/paraformer.cpp](https://github.com/lovemefan/paraformer.cpp)
- [ONNX Runtime CoreML Execution Provider](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)
- [中文语音识别模型对比](https://cloud.tencent.com/developer/article/2642961)
