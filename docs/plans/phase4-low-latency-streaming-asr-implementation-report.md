# Phase 4: 本地低延迟流式 ASR - 实现完成报告

## 实现日期
2026-04-02

## 实现内容

### 1. StreamingASREngine.swift（新建）

低延迟流式 ASR 引擎核心，使用滑动窗口和重叠拼接算法。

#### 核心配置

```swift
struct Config {
    var windowSizeMs: Int = 400          // 窗口时长
    var windowStepMs: Int = 100          // 窗口步进
    var sampleRate: Int = 16000          // 采样率
    var enableOverlapAdd: Bool = true    // 重叠拼接
    var minEnergyThreshold: Float = 0.001 // 能量阈值
}
```

#### 滑动窗口参数

| 参数 | 值 | 说明 |
|------|-----|------|
| windowSize | 6400 样本 | 400ms @ 16kHz |
| windowStep | 1600 样本 | 100ms @ 16kHz |
| overlapSize | 4800 样本 | 75% 重叠 |

#### 核心 API

| 方法 | 说明 |
|------|------|
| `start(resultCallback:)` | 启动引擎 |
| `stop()` | 停止引擎 |
| `appendAudio(_:)` | 接收 PCM 音频 |
| `flush()` | 刷新剩余缓冲 |
| `reset()` | 重置状态 |

#### 处理流程

```
音频流 → 缓冲累积 → 窗口提取 → 能量检测 → 窗函数 → ASR 推理 → 结果输出
                        ↓
                    汉宁窗 (Hanning)
```

### 2. SherpaStreamingProvider.swift（新建）

基于 sherpa-onnx 的低延迟流式提供者。

#### 与标准 SherpaOnnxProvider 的区别

| 特性 | SherpaOnnxProvider | SherpaStreamingProvider |
|------|-------------------|------------------------|
| 处理模式 | 批量/CLI 调用 | 实时流式 |
| 延迟 | 高（等待完整音频） | 低（每 100ms 输出）|
| 重叠处理 | 无 | 75% 重叠 |
| 部分结果 | 无 | 有 |
| 置信度过滤 | 无 | 有 |

#### 配置参数

```swift
struct Config {
    var windowSizeMs: Int = 400       // 窗口时长
    var windowStepMs: Int = 100       // 窗口步进
    var overlapRatio: Float = 0.5     // 重叠比例
    var minConfidence: Float = 0.3    // 最小置信度
}
```

### 3. AudioPreprocessor.swift（新建）

实时音频增强模块。

#### 功能

1. **直流偏移移除 (DC Offset Removal)**
   - 计算音频均值并减去
   - 消除硬件偏置

2. **自动增益控制 (AGC)**
   - 目标能量：0.1
   - 增益平滑因子：0.01
   - 增益范围：0.5 - 5.0
   - 防止削波限幅

#### 处理链

```
输入 → DC 移除 → AGC → 限幅 → 输出
```

## 技术亮点

### 1. 滑动窗口算法

```
时间轴： |----1----|----2----|----3----|----4----|
窗口 1:  [======== 6400 样本 ========]
窗口 2:            [======== 6400 样本 ========]
窗口 3:                        [======== 6400 样本 ========]
步进：             ↑
                  1600 样本 (100ms)
重叠：             <------- 4800 样本 (75%) ------->
```

**优势：**
- 每 100ms 输出一次结果，延迟远低于批量处理
- 75% 重叠确保边界信息不丢失
- 汉宁窗减少频谱泄漏

### 2. 汉宁窗（Hanning Window）

```swift
w[n] = 0.5 * (1 - cos(2πn/N))
```

应用于每个窗口，减少边界不连续：
- 窗口两端平滑衰减到 0
- 减少频谱泄漏
- 改善 ASR 识别准确率

### 3. 能量检测

```swift
energy = sqrt(sum(samples^2) / count)
guard energy > minEnergyThreshold else {
    return emptySegment  // 静音跳过
}
```

**优势：**
- 跳过静音窗口，节省计算资源
- 只在有语音时触发 ASR

### 4. 置信度过滤

```swift
if segment.text.isEmpty || segment.text.count < 2 {
    return  // 过滤低质量结果
}
```

**优势：**
- 避免单字抖动
- 提升用户体验

### 5. 与 TranscriptStabilizer 集成

```
SherpaStreamingProvider → ASRSegment 流 → TranscriptStabilizer → 稳定文本
                            ↓
                      每 100ms 更新
```

**延迟分析：**
- 窗口时长：400ms
- 输出间隔：100ms
- 稳定器冻结：2000ms
- **端到端延迟：~2.5 秒**（冻结）/ ~500ms（预览）

## 性能特征

| 指标 | 值 | 说明 |
|------|-----|------|
| 窗口处理延迟 | 400ms | 单个窗口时长 |
| 输出更新频率 | 10Hz | 每 100ms |
| 重叠率 | 75% | 4800/6400 样本 |
| 计算开销 | 中等 | FFT+ 汉宁窗+ASR |
| 内存占用 | ~25KB | 缓冲 + 窗口 |

## 使用示例

```swift
// 创建提供者
let provider = SherpaStreamingProvider(config: .init(
    windowSizeMs: 400,
    windowStepMs: 100,
    overlapRatio: 0.75
))

// 启动流式
let stream = try await provider.startStreaming(hotwords: ["术语"])

// 发送音频
Task {
    for try await segment in stream {
        print("Partial: \(segment.text)")
    }
}

// 音频输入
await provider.sendAudio(pcmData)  // 每 100ms 调用

// 结束
await provider.stopStreaming()
```

## 与 Phase 2/3 的协同

```
音频流 → Phase 2 VAD → Phase 4 流式 ASR → Phase 3 稳定器 → 最终文本
            ↓                    ↓               ↓
        激活/静音            100ms 输出        冻结/半稳定/活跃
```

**协同效应：**
- VAD 控制何时开始/停止流式
- 流式 ASR 提供高频率部分结果
- 稳定器平滑输出，避免抖动

## 后续优化建议

1. **自适应窗口大小** - 根据语速动态调整窗口
2. **多模型融合** - 同时运行多个 ASR 模型投票
3. **增量解码** - 基于前缀重用，减少重复计算
4. **SIMD 优化** - 使用 Accelerate 框架优化 FFT
5. **模型热加载** - 后台预加载模型，减少冷启动

## 文件清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `Services/StreamingASREngine.swift` | 新建 | 流式引擎核心 |
| `Services/SherpaStreamingProvider.swift` | 新建 | 低延迟提供者 |
| `Services/AudioPreprocessor.swift` | 新建 | 音频增强 |

## 验证结果

- ✅ 构建成功
- ✅ 24/24 测试通过
- ✅ 无回归

---

**Phase 4 已完成**。低延迟流式 ASR 基础架构已就绪，可支持后续 Phase 5（策略后处理与个性化）的开发。
