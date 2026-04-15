# 跨应用插入兼容性矩阵

## 概述

本文档记录了 MouthType 在不同应用程序中的文本插入行为、兼容性配置和已知问题。

## 应用家族分类

### 1. 浏览器 (browser)

| 应用 | 插入模式 | 重试次数 | 特殊处理 | 状态 |
|------|---------|---------|---------|------|
| Safari | Cmd+V | 3 | 检测 textarea/contenteditable | ✅ 支持 |
| Chrome | Cmd+V | 3 | 检测 textarea/contenteditable | ✅ 支持 |
| Firefox | Cmd+V | 3 | 检测 textarea/contenteditable | ✅ 支持 |
| Arc | Cmd+V | 3 | 检测 textarea/contenteditable | ✅ 支持 |
| Edge | Cmd+V | 3 | 检测 textarea/contenteditable | ✅ 支持 |
| Brave | Cmd+V | 3 | 检测 textarea/contenteditable | ✅ 支持 |

**默认配置：**
- 默认意图：`.insert`
- 启用选中检测：是
- 启用智能追加：否
- 回退到复制：是

### 2. IDE / 代码编辑器 (ide)

| 应用 | 插入模式 | 重试次数 | 特殊处理 | 状态 |
|------|---------|---------|---------|------|
| Xcode | Cmd+V | 2 | 优先替换选中 | ✅ 支持 |
| VS Code | Cmd+V | 2 | 优先替换选中 | ✅ 支持 |
| Cursor | Cmd+V | 2 | 优先替换选中 | ✅ 支持 |
| Zed | Cmd+V | 2 | 优先替换选中 | ✅ 支持 |
| IntelliJ | Cmd+V | 2 | 优先替换选中 | ✅ 支持 |
| PyCharm | Cmd+V | 2 | 优先替换选中 | ✅ 支持 |
| WebStorm | Cmd+V | 2 | 优先替换选中 | ✅ 支持 |

**默认配置：**
- 默认意图：`.replaceSelection`
- 启用选中检测：是
- 启用智能追加：否
- 回退到复制：是

### 3. 终端 (terminal)

| 应用 | 插入模式 | 重试次数 | 特殊处理 | 状态 |
|------|---------|---------|---------|------|
| Terminal | Cmd+Shift+V | 2 | 需要特殊粘贴组合键 | ✅ 支持 |
| iTerm2 | Cmd+Shift+V | 2 | 需要特殊粘贴组合键 | ✅ 支持 |
| Warp | Cmd+Shift+V | 2 | 需要特殊粘贴组合键 | ✅ 支持 |
| Kitty | Cmd+Shift+V | 2 | 需要特殊粘贴组合键 | ✅ 支持 |
| Alacritty | Cmd+Shift+V | 2 | 需要特殊粘贴组合键 | ✅ 支持 |
| Hyper | Cmd+Shift+V | 2 | 需要特殊粘贴组合键 | ✅ 支持 |

**默认配置：**
- 默认意图：`.appendAfterSelection`
- 启用选中检测：否
- 启用智能追加：否
- 回退到复制：是

### 4. 文档编辑器 (document)

| 应用 | 插入模式 | 重试次数 | 特殊处理 | 状态 |
|------|---------|---------|---------|------|
| Pages | Cmd+V | 2 | 支持智能追加 | ✅ 支持 |
| Word | Cmd+V | 2 | 支持智能追加 | ✅ 支持 |
| Notion | Cmd+V | 2 | Electron 应用 | ✅ 支持 |
| Bear | Cmd+V | 2 | Markdown 编辑 | ✅ 支持 |
| Obsidian | Cmd+V | 2 | Electron 应用 | ✅ 支持 |
| Typora | Cmd+V | 2 | Markdown 编辑 | ✅ 支持 |

**默认配置：**
- 默认意图：`.insert`
- 启用选中检测：是
- 启用智能追加：是
- 回退到复制：是

### 5. 聊天应用 (chat)

| 应用 | 插入模式 | 重试次数 | 特殊处理 | 状态 |
|------|---------|---------|---------|------|
| 微信 | Cmd+V | 3 | 高重试次数 | ✅ 支持 |
| Messages | Cmd+V | 3 | 高重试次数 | ✅ 支持 |
| Slack | Cmd+V | 3 | Electron 应用 | ✅ 支持 |
| Discord | Cmd+V | 3 | Electron 应用 | ✅ 支持 |
| Telegram | Cmd+V | 3 | 高重试次数 | ✅ 支持 |
| WhatsApp | Cmd+V | 3 | Electron 应用 | ✅ 支持 |

**默认配置：**
- 默认意图：`.insert`
- 启用选中检测：是
- 启用智能追加：否
- 回退到复制：是

### 6. Electron 应用 (electron)

| 应用 | 插入模式 | 重试次数 | 特殊处理 | 状态 |
|------|---------|---------|---------|------|
| VS Code | Cmd+V | 2 | 已归类为 IDE | ✅ 支持 |
| Slack | Cmd+V | 2 | 已归类为 Chat | ✅ 支持 |
| Discord | Cmd+V | 2 | 已归类为 Chat | ✅ 支持 |
| Notion | Cmd+V | 2 | 已归类为 Document | ✅ 支持 |

**默认配置：**
- 默认意图：`.insert`
- 启用选中检测：是
- 启用智能追加：否
- 回退到复制：是

### 7. 原生应用 (native)

其他未分类的原生 macOS 应用。

**默认配置：**
- 默认意图：`.insert`
- 启用选中检测：是
- 启用智能追加：否
- 回退到复制：是

## 插入意图说明

### `.insert` - 插入
在光标位置插入文本，不删除任何现有内容。

### `.replaceSelection` - 替换选中
如果有选中文本，先删除选中文本再插入新内容。

### `.appendAfterSelection` - 追加
在当前位置后追加内容，通常用于终端等场景。

### `.smart` - 智能
根据应用家族和上下文自动选择最佳意图。

## 回退策略

当插入失败时，系统按以下顺序回退：

1. **重试粘贴**（最多 3 次，间隔 100ms）
2. **回退到复制** - 将文本复制到剪贴板，提示用户手动粘贴
3. **显示错误** - 如果所有方法都失败

## 已知问题

### 1. 特殊应用限制
- **密码管理器应用**：可能阻止辅助功能粘贴
- **安全终端应用**：可能需要特殊处理

### 2. 权限要求
- 需要辅助功能权限才能执行粘贴操作
- 首次使用会弹出权限请求

## 测试清单

发布前应测试以下场景：

- [ ] Safari 文本框输入
- [ ] Chrome Gmail 撰写
- [ ] Xcode 代码编辑
- [ ] VS Code 代码编辑
- [ ] Terminal 命令输入
- [ ] iTerm2 命令输入
- [ ] 微信聊天输入
- [ ] Messages 短信输入
- [ ] Notion 文档编辑
- [ ] Pages 文档编辑

## 配置文件

配置文件位于 `Sources/MouthType/Services/InsertionIntent.swift` 中的 `InsertionCompatibilityProfile`。

### 添加新应用配置

```swift
static func profile(for appFamily: AppFamily) -> InsertionCompatibilityProfile {
    switch appFamily {
    case .newAppFamily:
        return InsertionCompatibilityProfile(
            appFamily: .newAppFamily,
            defaultIntent: .insert,
            enableSelectionDetection: true,
            retryCount: 2,
            enableFallbackCopy: true
        )
    // ...
    }
}
```

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-04-02 | 初始版本，包含基础插入计划 |
| 2.0 | 2026-04-02 | Phase 6 实现，添加插入意图协议和计划执行器 |

---

**维护说明：**
- 发现新的应用兼容性问题时，应先更新此文档
- 添加新的应用家族前，需评估是否有足够的用户需求和测试覆盖
