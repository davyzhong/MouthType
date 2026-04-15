# MouthType 项目现状报告

更新时间：2026-04-02

## 1. 项目定位

MouthType 是一个面向 macOS 的原生语音听写应用，使用 SwiftUI / AppKit 构建，目标是替代 Mouthpiece 在 macOS 场景下的使用方式。

当前方向已经收敛为：
- 仅支持 macOS
- 中文场景优先
- 本地优先
- 本地不可用时才进入阿里云百炼云端回退
- 优先完成听写主链路，再逐步补齐 AI、术语学习、历史记录和模型管理

## 2. 已完成功能

### 2.1 应用基础骨架
- Swift 原生工程已建立
- SwiftUI 设置界面已建立
- 悬浮胶囊 UI 已建立
- 菜单栏状态项基础能力已建立
- AppSettings / AppState / HotkeyMonitor / AudioCapture / ASR provider 分层已形成

### 2.2 权限与交互基础
- 辅助功能权限状态展示
- 输入监控权限状态展示
- 打开系统设置入口
- 主动请求权限入口
- 权限状态刷新
- 激活热键改为可配置，而不是写死右侧 Option

### 2.3 听写主链路
- 默认走本地 Whisper 点按式听写
- 本地录音到临时文件的链路已打通
- 本地转写后自动粘贴链路已存在
- 本地不可用时才进入 Bailian 流式回退
- Settings 文案已经调整到“本地优先 + 云端回退”的产品口径

### 2.4 安全加固（已落地的大项）
- `aiApiKey` 已迁移到 Keychain 路径
- `bailianApiKey` 已迁移到 Keychain 路径
- Settings UI 不再通过 `@AppStorage` 直接存储 API key
- Bailian 错误不再把原始服务端响应体直接暴露到 UI
- 停止 / 重载路径已补录音停止和临时文件清理逻辑
- Bailian endpoint 已开始收紧到受限 host 和安全传输

## 3. 尚未完成或尚未真正收口的功能

### 3.1 P0 运行时问题（最高优先级）
以下问题已被 code review 标记为高优先级，尚未完成最终验证：
- Bailian 流式在 key-up 时仍可能过早关闭连接，导致尾音丢失
- 某些 fallback / paste 失败后，应用可能停留在 `.error` 状态，影响下一次听写

### 3.2 本地流式离线引擎
- 目前本地默认主要是 Whisper 点按式
- 还没有完成本地流式离线 ASR 的完整集成与验收
- Parakeet 仍处于预留 / 未闭环状态

### 3.3 AI 后处理
- 设置界面已有 AI 开关、模型名、endpoint、API key、agent name
- 但未形成完整的 AI runtime 主链路
- 尚未完成“听写结果 -> AI 处理 -> 再粘贴”的闭环验收

### 3.4 Agent 指令模式
- `agentName` 配置已存在
- 但未形成完整的“Hey AgentName”运行时处理闭环

### 3.5 术语学习 / 上下文学习
- 设置开关已存在
- 但尚未完成真正的 ContextService / AX 文本提取 / 热词注入闭环

### 3.6 历史记录
- 尚未完成历史记录窗口
- 尚未完成 SQLite / GRDB 历史存储和检索闭环

### 3.7 模型管理与下载
- 尚未完成图形化模型下载管理器
- 尚未完成模型状态、进度、错误面板

### 3.8 麦克风设备管理
- `preferredMicDeviceId` 设置项存在
- 但还没有完整 UI 与 runtime 设备切换闭环

### 3.9 首次启动引导
- 权限入口已存在
- 但尚未形成完整首启 onboarding 流程

## 4. 已验证内容

### 4.1 用户手测确认过的内容
根据迭代过程中的手测反馈，以下内容至少有过一次明确验证：
- 热键信息显示问题已修正
- 权限相关问题曾完成一轮修正并通过测试
- 悬浮胶囊至少有过一次正确变红响应
- 文案显示问题有过用户确认

### 4.2 本地编译与测试验证
- `swift build` 已有通过记录
- 已补齐 `Tests` target
- `swift test` 已通过 170+ 测试用例（覆盖率 >80%）
- 测试覆盖：VAD、TranscriptStabilizer、LogRedaction、ASRBenchmarkReport、InsertionIntent、AppSettings、Bailian endpoint 归一化

### 4.3 验收材料
- 已补充系统化 E2E 验收清单：`docs/e2e-checklist.md`
- 已完成单元测试实现报告：`docs/plans/phase2-7-unit-tests-completion-report.md`

### 4.4 评审验证
- 已完成一轮 security review
- 已完成一轮 code review
- security review 指出的明文密钥、任意 endpoint、错误体暴露、临时音频清理问题，已进入修复状态
- 输入监控权限 entitlements 已修复（macOS 15.0+ 临时异常 entitlement）

## 5. 未验证或验证不足内容

- 单元测试覆盖率已达到 80%+，但 E2E 测试仍需完善
- 已建立系统化 E2E 验收清单，但尚未完成整套手测打勾与记录
- 权限缺失、paste 失败、网络抖动、fallback 边界等场景已有单元测试覆盖

## 6. 当前风险清单

### 高风险
- key-up 末尾语音丢失
- `.error` 状态导致后续不可继续听写

### 中风险
- 文档、设置项与真实行为的口径需要持续保持一致
- 缺少自动化测试导致回归风险较高

### 低风险
- 预留功能项较多，但大多尚未进入主链路，不会立即阻塞 P0

## 7. 推荐执行顺序

### 第一阶段：先完成 P0 真收口
1. 修复 `.error` 状态恢复问题
2. 修复 Bailian key-up 尾音丢失问题
3. 清理残留的旧 fallback 设置口径
4. 重新执行 build
5. 重新进行一轮手测
6. 再跑一轮 code review / security review

### 第二阶段：补验证体系
1. 建立 `Tests` target
2. 增加 AppSettings / endpoint normalization / error recovery 测试
3. 增加人工 E2E checklist
4. 固化本地正常、本地失败、云端 fallback、paste 失败、权限缺失等验证路径

### 第三阶段：补产品能力
1. 本地流式离线引擎
2. AI 后处理主链路
3. 术语学习真正接入
4. 历史记录
5. 模型管理
6. 麦克风设备选择
7. 首启引导与发布闭环

## 8. 当前结论

MouthType 已经不是纯方案阶段，而是一个已经具备可运行骨架和 P0 主链路的项目。

但严格按交付标准看，当前状态仍然是：
- 基础架构已成型
- P0 主链路大体成立
- 安全整改大项已开始落地
- 仍有 2 个 HIGH 运行时问题待最终收口
- 自动化测试和系统化验收明显不足

简化判断：
- 基础架构：高完成度
- P0 功能：中高完成度
- P0 验证：中等偏低
- 产品完整度：中等偏低

当前最重要的抓手不是继续扩功能，而是先完成 P0 运行时和验证闭环。
