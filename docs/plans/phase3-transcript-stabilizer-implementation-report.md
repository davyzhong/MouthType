# Phase 3: 增量转写稳定器 - 实现完成报告

## 实现日期
2026-04-02

## 实现内容

### 1. TranscriptStabilizer.swift（新建）

实现了增量转写稳定器，管理流式 ASR 的部分结果，防止文本抖动。

#### 三区域架构

```
[冻结区域] | [半稳定区域] | [活跃区域]
   frozen   |  semi-stable |   active
```

**冻结区域 (Frozen)**
- 已最终确认的文本，不再修改
- 超过 `freezeWindowSeconds` (2.0 秒) 的片段自动冻结
- 适合直接粘贴到目标应用

**半稳定区域 (Semi-Stable)**
- 较早期的部分结果，相对稳定但可能微调
- 超过 `semiStableWindowSeconds` (0.8 秒) 的片段进入此区域
- 适合 UI 实时预览

**活跃区域 (Active)**
- 最新的转写结果，可能频繁变化
- 每次 ASR 更新都可能重写
- 仅用于内部追踪

#### 核心配置

```swift
struct Config {
    var freezeWindowSeconds: TimeInterval = 2.0      // 冻结窗口
    var semiStableWindowSeconds: TimeInterval = 0.8  // 半稳定窗口
    var minCommitLength: Int = 3                     // 最小提交长度
    var dedupToleranceSeconds: TimeInterval = 0.3    // 去重容差
}
```

#### 核心 API

| 方法 | 说明 |
|------|------|
| `append(_:referenceTime:)` | 接收单个 ASR 片段 |
| `appendMany(_:referenceTime:)` | 批量接收片段 |
| `getFrozenText()` | 获取已冻结文本 |
| `getStableText()` | 获取稳定文本（冻结 + 半稳定）|
| `getFullText()` | 获取完整文本（所有区域）|
| `flush()` | 强制提交活跃区域 |
| `reset()` | 重置状态 |

#### 回调机制

```swift
var onFrozenTextAdded: (@Sendable (String) -> Void)?
var onStableTextUpdated: (@Sendable (String) -> Void)?
```

- `onFrozenTextAdded` - 当有新文本冻结时调用
- `onStableTextUpdated` - 当稳定文本更新时调用（用于 UI 实时更新）

### 2. HotkeyMonitor.swift（修改）

集成 TranscriptStabilizer 到流式转写流程。

#### 新增状态

```swift
private let stabilizer = TranscriptStabilizer()
private var stabilizerSessionId: String = ""
```

#### startLocalStreamingMode 更新

```swift
// 1. 创建新会话
stabilizerSessionId = UUID().uuidString
stabilizer.reset()

// 2. 绑定回调
stabilizer.onFrozenTextAdded = { newText in ... }
stabilizer.onStableTextUpdated = { stableText in
    self.appState.streamingText = stableText
}

// 3. 处理 ASR 片段
for try await segment in stream {
    stabilizer.append(segment)
    self.appState.streamingText = stabilizer.getStableText()
}
```

#### stopLocalStreamingAndPaste 更新

```swift
// 1. 刷新稳定器
let remainingText = stabilizer.flush()

// 2. 获取完整文本
let text = stabilizer.getFullText()

// 3. 重置状态
stabilizer.reset()
stabilizerSessionId = ""
```

### 3. BailianStreamingProvider.swift（无需修改）

Bailian 流式提供者已经返回 `ASRSegment` 结构，天然支持稳定器。
只需在 `HotkeyMonitor` 中统一通过稳定器处理即可。

## 技术亮点

### 1. 时间驱动区域晋升

```swift
// 冻结边界计算
let freezeThreshold = referenceTime - config.freezeWindowSeconds
let newFrozenCount = segments.firstIndex { $0.endTime > freezeThreshold }
```

片段根据 `endTime` 与当前参考时间的差值自动晋升：
- `endTime < referenceTime - 2.0s` → 冻结
- `endTime < referenceTime - 0.8s` → 半稳定
- 其他 → 活跃

### 2. 无抖动 UI 更新

稳定器确保：
- 冻结文本一旦确认就不再变化
- UI 显示的是稳定文本（冻结 + 半稳定），避免活跃区域的频繁跳动
- 只有真正新的冻结文本才会触发 `onFrozenTextAdded`

### 3. 会话级状态管理

每个录音会话独立：
- `stabilizerSessionId` 追踪当前会话
- 会话开始时 `reset()`
- 会话结束时 `flush()` 获取剩余文本
- 防止跨会话污染

### 4. 去重保护

```swift
func isDuplicate(text: String, currentTime: TimeInterval) -> Bool
```

检测短时间内的重复文本，避免同一内容多次粘贴。

## 集成示例

```swift
// 开始会话
stabilizer.reset()
stabilizerSessionId = UUID().uuidString

// 处理 ASR 流
for try await segment in asrStream {
    stabilizer.append(segment)
    
    // UI 显示稳定文本
    display(stabilizer.getStableText())
}

// 结束会话
stabilizer.flush()
let finalText = stabilizer.getFullText()
paste(finalText)
```

## 性能特征

| 操作 | 时间复杂度 | 说明 |
|------|------------|------|
| `append` | O(1) | 追加片段 |
| `getFrozenText` | O(n) | n=冻结片段数 |
| `getStableText` | O(n) | n=稳定片段数 |
| `getFullText` | O(n) | n=总片段数 |
| `flush` | O(1) | 标记所有为冻结 |

内存占用：每片段约 100 字节（文本 + 时间戳 + UUID）
典型会话（30 秒，每秒 3 片段）：约 10KB

## 测试状态

- ✅ 构建成功
- ✅ 24/24 单元测试通过
- ✅ 无回归测试失败

## 与 Phase 2 VAD 的协同

Phase 3 稳定器与 Phase 2 VAD 无缝集成：

```
音频流 → VAD 检测 → ASR 转写 → 稳定器 → 最终文本
                   (Sherpa)   (3 区域)   (冻结输出)
```

- VAD 控制"何时开始/停止"转写
- 稳定器控制"如何平滑"转写结果
- 两者独立工作，互不干扰

## 后续优化建议

1. **动态窗口调整** - 根据语速自适应调整冻结窗口
2. **文本相似度去重** - 使用编辑距离检测近似重复
3. **标点稳定策略** - 标点符号延迟冻结，避免频繁增减
4. **多 ASR 融合** - 同时接收多个 ASR 结果，投票决定稳定文本

## 文件清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `Services/TranscriptStabilizer.swift` | 新建 | 稳定器核心实现 |
| `Platform/HotkeyMonitor.swift` | 修改 | 集成稳定器 |

## 下一步

Phase 3 已完成，建议继续实现：

- **Phase 4**: 本地低延迟流式 ASR 优化（滑动窗口、重叠拼接）
- **Phase 5**: 策略后处理与个性化增强
