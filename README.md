# MouthType

macOS 原生语音听写应用。基于 SwiftUI，本地优先，面向国内用户。

## 当前状态

- ✅ P0 主链路完成（2026-04-16）
- ✅ 全面代码审查完成（13 项问题全部修复）
- ✅ 性能优化完成（音频处理管道 4 项优化）
- ✅ 死代码清理完成
- ✅ 无编译警告、无编译错误
- ✅ 无 HIGH 运行时问题

## 已落地能力

- 原生 SwiftUI + AppKit 应用骨架
- 悬浮胶囊与菜单栏入口
- 权限状态展示与系统设置跳转（辅助功能、输入监控）
- 可配置热键
- 本地 Whisper 点按式听写
- Bailian 流式回退（带 WebSocket 自动重连）
- Keychain 化的 API key 存储路径
- 智能粘贴服务（跨应用插入兼容性）
- 完整的单元测试覆盖（170+ 测试用例，覆盖率 >80%）
- 带 entitlements 的构建脚本（支持 macOS 15.0+ 输入监控权限）
- 模型下载 SHA256 校验和验证
- 错误状态自动恢复（3 秒）

## 性能特性

- **AudioRingBuffer**: 批量写入减少锁竞争，16kHz 下每秒减少 16000 次锁操作
- **VADProcessor**: 优化的语音活动检测，无冗余计算
- **FloatingCapsule**: 音频级别动画节流（50ms → 120ms），降低 GPU 负载
- **AppState**: 音频级别更新限流（100ms），减少 UI 刷新频率

## 代码质量

- 全面代码审查通过（安全性、线程安全、错误处理、代码质量）
- 死代码清理完成（4 个未使用变量，1 个未使用方法）
- Sendable 并发警告修复
- 线程安全文档完善（@unchecked Sendable 类均添加说明）
- 日志脱敏增强（身份证、银行卡、手机号、微信、URL）

## 技术栈

- SwiftUI + AppKit (NSPanel, NSStatusItem)
- AVAudioEngine (音频采集)
- whisper.cpp / sherpa-onnx (本地 ASR)
- 阿里云百炼 Paraformer (云端 ASR fallback + AI 后处理预留)
- SQLite.swift (SQLite 存储)
- IOKit / AXUIElement (热键 + 上下文感知)
- XCTest (单元测试)
