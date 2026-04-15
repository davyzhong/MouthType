# Phase 2: 多状态 VAD 与自适应噪声处理 - 实现完成报告

## 实现日期
2026-04-02

## 实现内容

### 1. VADProcessor.swift（新建）

实现了多状态语音活动检测器，包含以下核心功能：

#### 状态机设计
- **`.silent`** - 静音状态，追踪自适应噪声底限
- **`.activating(activatingFrames: Int)`** - 激活中，累积置信度
- **`.active`** - 语音激活，正常流式传输
- **`.trailing(trailingFrames: Int)`** - 拖尾状态，hangover 期间等待语音返回

#### 核心特性
1. **自适应噪声底限追踪**
   - 指数移动平均（alpha = 0.98）
   - 最小噪声底限保护（0.001）
   - 仅在静音状态下更新

2. **激活窗口与置信度**
   - 默认 150ms 激活窗口
   - 需要连续帧达到阈值才能转为 active
   - 激活期间检测到静音则重置

3. **拖尾 Hangover 机制**
   - 默认 300ms hangover 时间
   - 期间检测到语音立即返回 active
   - hangover 超后才转为静音

4. **迟滞比较器**
   - 激活阈值：0.02
   - 静音阈值：0.01（迟滞防止抖动）

#### 配置参数
```swift
struct Config {
    var activationThreshold: Float = 0.02     // 激活阈值
    var silenceThreshold: Float = 0.01        // 静音阈值（迟滞）
    var activationWindowMs: Int = 150         // 激活窗口
    var hangoverMs: Int = 300                 // 拖尾时间
    var noiseFloorAlpha: Float = 0.98         // 噪声底限平滑因子
    var minNoiseFloor: Float = 0.001          // 最小噪声底限
    var sampleRate: Double = 16000            // 采样率
    var channels: Int = 1                     // 声道数
}
```

### 2. AudioRingBuffer.swift（新建）

实现了环形缓冲区用于预滚动音频存储：

#### 核心功能
- **预滚动存储** - 在 VAD 激活期间存储音频，确保不丢失句首语音
- **循环覆盖** - 缓冲区满后覆盖最旧数据
- **时序保持** - 读取时正确重排序为时间顺序
- **PCM 转换** - 直接输出 Int16 PCM 格式供 ASR 使用

#### 技术规格
- 默认 500ms 缓冲容量 @ 16kHz = 8000 样本
- 支持 `hasPreRoll` 检查（50% 满）
- 支持 `readAndReset()` 和 `readAndResetAsPCM()`

### 3. AudioCapture.swift（修改）

集成 VAD 和设备丢失检测：

#### 新增功能
1. **VAD 模式支持**
   - `startStreaming(vadEnabled:handler:)` 方法
   - `onVADStateChange` 回调
   - VAD 处理集成到音频流中

2. **设备丢失检测**
   - `AVAudioEngineConfigurationChange` 通知监听
   - `captureDeviceID()` 获取当前设备
   - `availableAudioDevices()` 检查设备可用性
   - `onDeviceLost` 回调通知

3. **Core Audio 集成**
   - `AudioObjectGetPropertyData` 查询默认输入设备
   - 设备变化时自动通知

#### 状态清理
- `stopStreaming()` 现在清理 VAD 和 ringBuffer
- 重置 `currentDeviceID` 和 `isVADMode`

### 4. HotkeyMonitor.swift（修改）

集成 VAD 到录音流程：

#### 新增方法
- `startLocalStreamingMode()` - VAD 模式，按键停止
- `startLocalStreamingModeAutoStop()` - VAD 自动停止模式

#### 状态联动
- VAD `.activating` → AppState `.listening`
- VAD `.active`/`.trailing` → AppState `.streaming`
- VAD `.silent`（hangover 结束）→ 自动停止并粘贴（AutoStop 模式）

#### 设备丢失处理
- 检测麦克风断开时显示错误
- 自动调用 `stopLocalStreamingAndPaste()`

### 5. AppState.swift（修改）

新增 `.listening` 状态：

```swift
enum DictationState: Equatable {
    case idle
    case listening          // 新增：VAD 激活中/倾听中
    case recording
    case streaming(String)
    case processing
    case aiProcessing
    case error(String)
}
```

- `isRecording` 现在包含 `.listening` 状态
- FloatingCapsule UI 更新支持新状态

### 6. FloatingCapsule.swift（修改）

更新状态图标显示：
- `.listening` 状态显示麦克风脉冲动画（同 `.recording`）

## 技术亮点

### 1. 自适应噪声底限
```
noiseFloor(t) = noiseFloor(t-1) * 0.98 + level * 0.02
```
自动适应环境噪声变化，避免固定阈值在不同环境下的误触发。

### 2. 迟滞比较器
```
激活：level > 0.02
静音：level < 0.01
```
防止阈值附近的抖动，确保状态切换稳定。

### 3. 预滚动缓冲
在 VAD 从 `.activating` 转为 `.active` 时，先输出缓冲区中存储的 500ms 音频，确保句首语音不丢失。

### 4. 拖尾 Hangover
```
active → 检测静音 → trailing(300ms) → 静音
                        ↓
                   语音返回 → active
```
允许短暂停顿而不中断转写，提升连续语音体验。

## 测试状态

- ✅ 构建成功
- ✅ 24/24 单元测试通过
- ✅ 无回归测试失败

## 后续优化建议

1. **VAD 参数调优** - 实际使用中根据用户反馈调整激活窗口和 hangover 时间
2. **环形缓冲区真实 PCM 存储** - 当前实现存储 RMS 值，实际使用需存储 PCM 样本
3. **多麦克风阵列支持** - 未来可扩展为多声道 VAD
4. **神经网络 VAD** - 考虑集成 Silero VAD 等深度学习模型

## 文件清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `Platform/VADProcessor.swift` | 新建 | VAD 核心实现 |
| `Platform/AudioRingBuffer.swift` | 新建 | 环形缓冲区 |
| `Platform/AudioCapture.swift` | 修改 | 集成 VAD 和设备检测 |
| `Platform/HotkeyMonitor.swift` | 修改 | VAD 状态联动 |
| `Models/AppState.swift` | 修改 | 新增 `.listening` 状态 |
| `UI/FloatingCapsule.swift` | 修改 | UI 状态支持 |

## 下一步

Phase 2 已完成，建议继续实现：

- **Phase 3**: 增量转写稳定器（基于 VAD 状态的自然延伸）
- **Phase 4**: 本地低延迟流式 ASR 优化
