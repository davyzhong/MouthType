# MouthType

macOS 原生语音听写应用。基于 SwiftUI，本地优先，面向国内用户。

## 当前状态

- 当前方向：macOS only、中文优先、本地优先、百炼仅作回退
- 当前阶段：P0 主链路完成，单元测试覆盖率 >80%，准备发布测试
- 状态报告：[当前项目现状](docs/current-status.md)
- P0 执行计划：[P0 执行计划](docs/p0-execution-plan.md)
- E2E 验收清单：[E2E 验收清单](docs/e2e-checklist.md)
- 设计文档：[设计计划](docs/design-plan.md)

## 已落地能力

- 原生 SwiftUI + AppKit 应用骨架
- 悬浮胶囊与菜单栏入口
- 权限状态展示与系统设置跳转（辅助功能、输入监控）
- 可配置热键
- 本地 Whisper 点按式听写
- Bailian 流式回退（仅本地不可用时）
- Keychain 化的 API key 存储路径
- 智能粘贴服务（跨应用插入兼容性）
- 完整的单元测试覆盖（146+ 测试用例）
- 带 entitlements 的构建脚本（支持 macOS 15.0+ 输入监控权限）

## 仍在收口的重点

- Bailian key-up 收尾阶段的尾音完整性
- `.error` 状态后的恢复能力
- 自动化测试和 E2E 验收清单

## 技术栈

- SwiftUI + AppKit (NSPanel, NSStatusItem)
- AVAudioEngine (音频采集)
- whisper.cpp / sherpa-onnx (本地 ASR)
- 阿里云百炼 Paraformer (云端 ASR fallback + AI 后处理预留)
- SQLite.swift (SQLite 存储)
- IOKit / AXUIElement (热键 + 上下文感知)
- XCTest (单元测试)
