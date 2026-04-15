# MouthType P0 执行计划

更新时间：2026-04-02

## 目标

围绕当前已经明确的 P0 问题，先完成运行时安全与稳定性收口，再补齐最小验证基础设施，确保 MouthType 的本地优先听写链路满足以下约束：

1. 默认本地听写，不因一般性本地失败而自动上传音频到云端
2. 云端 fallback 只在“本地 ASR 不可用”这一明确边界触发
3. 流式 fallback 在 key-up 后能够稳定完成收尾，不挂起、不吞尾音
4. `.error` 状态后可以恢复到下一次可用录音会话
5. 至少具备最小 Swift 测试入口与人工 E2E 验收清单

## 已确认问题

### P0-1 隐私边界过宽
位置：`Sources/MouthType/Platform/HotkeyMonitor.swift`

现状：
- `tapTranscribe()` 中本地 Whisper 转写失败后，会直接调用 `bailianProvider.transcribe(audioURL:)`
- 这意味着“本地运行时失败”也会把录音上传到百炼

影响：
- 与当前产品承诺不一致
- 与设置文案不一致
- 用户可能在未预期情况下把音频发到云端

目标：
- 只允许“本地 ASR 不可用”触发 fallback
- “本地可用但本次失败”应直接报错并留在本地边界内

### P0-2 流式停止可能无法完成
位置：
- `Sources/MouthType/Platform/HotkeyMonitor.swift`
- `Sources/MouthType/Services/BailianStreamingProvider.swift`

现状：
- `stopStreamingAndPaste()` 里等待 `await streamTask?.value`
- 但 provider 的正常 stop/cancel 路径未必会 `finish()` continuation
- 结果可能是主流程永远等不到结束

影响：
- key-up 后卡住
- 不回到 idle
- 文本不粘贴或粘贴不稳定

目标：
- stop 是显式、可收敛、可完成的
- 正常停止时 consumer 一定能退出
- 保证最终文本收口逻辑只走一次

### P0-3 `.error` 恢复能力需要系统化收口
位置：主要在 `HotkeyMonitor.swift` 与 `AppState.swift`

现状：
- 已做过一轮 `.error -> .idle` 恢复补丁
- 但还没有覆盖所有失败路径的统一验证

风险：
- 某些失败后 UI 可见恢复，但运行态没有真正恢复
- 热键、录音、stream stop、paste 的后续会话可能受污染

目标：
- 所有失败出口都能回到可再次录音的稳态
- 清理临时状态：录音 URL、stream task、final text、audio level、fallback mode

### P1-1 已补齐 Swift Tests 入口
现状：
- 已新增 `Tests` target
- `swift test --package-path /Users/Davy/workspace-bak/MouthType` 已可运行并通过

影响：
- 已具备最小回归守护能力
- 当前覆盖仍以 endpoint 归一化等纯逻辑边界为主

目标：
- 在现有基础上继续补 error recovery / stream teardown 等回归测试

### P1-2 缺少人工 E2E 验证清单
现状：
- 有零散验证结论
- 没有统一 checklist

影响：
- 每次改动都容易漏验关键链路
- 权限 / 热键 / 本地 / fallback / 粘贴 无法系统回归

目标：
- 固化成项目文档
- 作为每次 P0/P1 收口的标准验收单

## 执行分阶段

### Phase 1：运行时修复
优先级最高，先解决“会错、会挂、会越边界”的问题。

#### 1. Restrict cloud fallback boundary
改动目标：
- 调整 `tapTranscribe()` 的 fallback 判定
- 仅在“本地 ASR 不可用”时允许走 Bailian
- 本地运行时失败直接进入 error，不上传音频

验收标准：
- Whisper 模型缺失 / 本地 provider unavailable：允许 fallback
- Whisper 转写过程报错但 provider 可用：不 fallback，直接 error
- 设置文案与运行时语义一致

#### 2. Fix streaming stop completion
改动目标：
- 显式区分“正常 stop”与“异常失败”
- 保证 `BailianStreamingProvider` 在 stop 后结束 stream
- 保证 `HotkeyMonitor` 不无限等待 `streamTask?.value`

验收标准：
- key-up 后稳定回到 idle
- 不出现长时间卡住
- 有最终文本就粘贴，没有文本就安静结束
- 不把主动 stop 误判为错误

#### 3. Verify and harden error recovery
改动目标：
- 梳理所有错误出口
- 确保状态清理统一
- 确保下一次热键可以重新开始

验收标准：
- 本地录音失败后能再次录音
- 本地转写失败后能再次录音
- 流式失败后能再次录音
- paste 失败后能再次录音

### Phase 2：验证基础设施
在 Phase 1 收口后立刻补最小验证能力。

#### 4. Add Swift regression tests
优先覆盖：
- `AppSettings` 的 Bailian endpoint 归一化与路径钉死
- 与本次修复直接相关的纯逻辑边界
- 可抽离出的状态清理/判定逻辑

验收标准：
- `swift test` 可运行
- 至少有一组回归测试覆盖本次 P0 修复中的纯逻辑约束

#### 5. Write E2E validation checklist
覆盖场景：
- 权限显示与跳转
- 热键按下/松开
- 本地 tap 听写
- 本地不可用 → 云端 fallback
- 本地运行时失败不上传
- 云端 stop 后不挂起
- `.error` 后恢复
- API key / endpoint / 设置页基本可用性

验收标准：
- 文档可直接照单执行
- 每项都有“预期结果”

## 实施顺序

1. 保存本执行计划文档
2. 修 P0-1：收紧云端 fallback 边界
3. 修 P0-2：修复流式正常 stop 的完成路径
4. 修 P0-3：统一 `.error` 恢复与状态清理
5. 建 `Tests` target，补最小回归测试
6. 写人工 E2E checklist
7. 跑 build / test / 手工清单做闭环

## 风险与注意事项

1. 不要把“stop 正常结束”继续混用成“error”
2. 不要为了通过 stop 而牺牲最终尾音收集
3. 不要把 fallback 条件写散在多个分支里，避免后面再次漂移
4. 测试优先写纯逻辑，不先碰重权限/重系统依赖的 UI 自动化

## 完成定义

满足以下条件才算 P0 收口完成：

- 本地失败不会越过隐私边界自动上云
- 云端流式 key-up 后不会卡死
- 关键错误后下一次会话能恢复
- `swift build` 通过
- `swift test` 可运行且有回归测试
- E2E checklist 文档落地并可执行
