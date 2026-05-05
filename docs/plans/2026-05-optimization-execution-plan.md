# MouthType 优化改造执行计划

> 生成时间：2026-05-05  
> 基于 Hermes 原计划优化  
> 状态：待执行

---

## 项目现状快照

| 指标 | 状态 |
|------|------|
| 技术栈 | Swift + SwiftUI + WebKit WebView（非 Electron） |
| 测试套件 | 158 个测试全部通过 ✅ |
| 编译状态 | `swift build` 无警告、无错误 ✅ |
| P0 主链路 | 已完成（本地 Whisper + 云端 Bailian fallback） ✅ |
| 代码审查 | 13 项问题全部修复 ✅ |
| E2E 验收 | 清单存在但未执行 ⏳ |

---

## 架构澄清

**重要**：原 Hermes 计划基于 Electron 架构描述（main.js、renderer process、npm 命令），但实际项目是 **Swift 原生 macOS 应用**：

| 原计划描述 | 实际架构 |
|------------|----------|
| Electron 36 + React 19 | Swift 5.9 + SwiftUI |
| main process / renderer process | 主进程 / WebKit WebView |
| preload.js 100+ IPC 通道 | preload.js 448 行 WebView 桥接 |
| `npm test` | `swift test` |
| `npm run build` | `swift build -c release` |

**本计划已针对实际 Swift 架构调整**。

---

## 执行策略

采用 4 阶段递进式改造，每阶段有明确的准入准出标准。

**阶段一和阶段二可以部分并行执行**。

---

## 阶段一：止血修复（目标：恢复开发基线）

**预计工时**：1-2 周  
**风险等级**：低

### 任务 1.1：修复 Info.plist 问题

**优先级**：最高  
**准入条件**：无  
**准出标准**：Info.plist 配置与应用行为一致

| 修改项 | 当前值 | 目标值 | 原因 |
|--------|--------|--------|------|
| LSUIElement | false | true | 浮动胶囊应用不应出现在 Dock |
| NSAppleEventsUsageUsageDescription | 拼写错误（双 Usage） | 修正拼写 | 权限描述准确性 |

**文件**：`Sources/MouthType/Info.plist`

---

### 任务 1.2：重写 CLAUDE.md

**优先级**：高  
**准入条件**：无  
**准出标准**：CLAUDE.md 与实际 Swift 架构一致，AI 能正确理解项目结构

| 步骤 | 操作 | 预计时间 |
|------|------|----------|
| 1 | 备份原 CLAUDE.md | 2 min |
| 2 | 删除所有 Electron 相关章节（main.js、helpers、React） | 10 min |
| 3 | 编写 Swift/SwiftUI 架构概述 | 20 min |
| 4 | 编写目录结构说明（Sources/MouthType/ 下的 Services/UI/Platform/Models） | 15 min |
| 5 | 编写 preload.js WebView 桥接说明 | 10 min |
| 6 | 编写构建方式（swift build / swift test） | 10 min |
| 7 | 编写代码签名和分发注意事项 | 10 min |

---

### 任务 1.3：执行 E2E 手工验收

**优先级**：高  
**准入条件**：阶段一其他任务完成  
**准出标准**：`docs/e2e-checklist.md` 全部打勾通过

**执行方式**：
1. 打印 E2E 清单
2. 逐项执行并记录结果（通过/失败/现象/截图）
3. 失败项记录复现条件和错误日志

**注意**：此任务无法自动化，必须人工执行。

---

## 阶段二：工程化基础建设

**预计工时**：2-3 周  
**风险等级**：中

### 任务 2.1：GitHub Actions CI

**准入条件**：阶段一完成  
**准出标准**：每次 push/PR 自动触发 build + test

**文件**：`.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      
      - name: Build
        run: swift build
      
      - name: Test
        run: swift test
      
      - name: Ad-hoc codesign
        run: codesign --force --deep --sign - .build/debug/MouthType
```

**后续迭代**：
- 添加 SwiftLint
- 添加 `-warnings-as-errors`
- 添加 codecov 上传

---

### 任务 2.2：合并构建脚本

**当前问题**：`build-app.sh` 和 `build-with-entitlements.sh` 逻辑重复，后者还会清除用户数据

**新文件**：`scripts/build.sh`

```bash
#!/bin/bash
# MouthType 统一构建脚本
# 用法：./scripts/build.sh [debug|release]

BUILD_MODE="${1:-debug}"

case "$BUILD_MODE" in
  debug)
    swift build
    codesign --force --deep --sign - .build/debug/MouthType
    ;;
  release)
    swift build -c release
    codesign --force --deep --sign - .build/release/MouthType
    ;;
  *)
    echo "Usage: $0 [debug|release]"
    exit 1
    ;;
esac
```

**功能**：
- 统一两套脚本逻辑
- 保留 entitlements 配置
- 移除用户数据清除逻辑
- 从 git tag 或 Info.plist 读取版本号注入

---

### 任务 2.3：preload.js 模块化拆分

**优先级**：中  
**准入条件**：阶段一完成  
**准出标准**：功能等价，代码结构清晰，攻击面减小

**拆分方案**：

```
preload/
├── index.js      # 聚合导出，保持 window.electronAPI 兼容
├── keys.js       # API key 管理
├── streaming.js  # 流式 ASR 相关
├── models.js     # 模型下载/管理
├── window.js     # 窗口控制
├── database.js   # 数据库 CRUD
└── system.js     # 剪贴板/热键/系统设置
```

**同步改造**：
- 所有事件监听统一使用 `registerListener` helper
- 添加 JSDoc 类型注释
- **Swift 侧 IPC handler 添加 URL 白名单校验**（openExternal、proxyRuntimeApiRequest）

**注意**：preload.js 是 WebKit WebView 的 `WKUserScript`，拆分后需确认注入方式是否需要调整。

---

### 任务 2.4：API Key 安全加固（评估 + 部分实施）

**优先级**：中  
**准入条件**：任务 2.3 完成  
**准出标准**：完成架构评估，至少收紧最敏感的 key

**方案 A（推荐，但改造成本高）**：main-process 代理模式
- renderer 通过 IPC 发送请求内容
- main process 持有 key 并执行实际 HTTP 请求
- renderer 永远接触不到 raw key

**方案 B（过渡方案）**：如果架构限制必须暴露
- 改为按需获取（非启动时全量）
- 添加 IPC 通道权限分级

**建议**：先评估改造成本，如过高则先用方案 B 过渡，仅收紧 `bailianApiKey`。

---

## 阶段三：质量提升

**预计工时**：3-4 周  
**风险等级**：中高

### 任务 3.1：分发签名与公证

**前置条件**：需要 Apple Developer ID（如没有需先申请，$99/年）

| 步骤 | 操作 | 预计时间 |
|------|------|----------|
| 1 | 配置 Developer ID 到构建脚本 | 2h |
| 2 | 添加 notarytool 公证步骤到 CI | 4h |
| 3 | 测试完整签名 + 公证流程 | 4h |
| 4 | 配置 Sparkle 自动更新（可选） | 8h |

---

### 任务 3.2：Swift 6 兼容性评估

**优先级**：中  
**准入条件**：阶段二完成

| 步骤 | 操作 | 预计时间 |
|------|------|----------|
| 1 | Package.swift 添加 `swiftLanguageVersions: [.v6]` | 30 min |
| 2 | 启用 `-strict-concurrency=complete` 编译检查 | 1h |
| 3 | **评估警告数量，决定策略** | 2h |
| 4 | 如警告过多，用 `@preconcurrency` 过渡关键路径 | 4h |
| 5 | 逐步添加 `@Sendable` 标注到跨 actor 传递的闭包 | 4h |

**风险**：`@unchecked Sendable` 类（如 `AudioManager`、`VADProcessor`）需要真正解决线程安全问题。

---

### 任务 3.3：本地流式离线引擎（可选）

**优先级**：取决于产品决策  
**说明**：当前 `current-status.md` 列为 P1 待完成，如优先级高可纳入此阶段

---

## 阶段四：持续改进（长期）

| 领域 | 行动项 | 优先级 |
|------|--------|--------|
| 监控 | 接入 Sentry 崩溃报告 | 中 |
| 性能 | Instruments 分析启动耗时 | 中 |
| 性能 | ASR 服务内存 profile | 低 |
| 文档 | 每次发布生成 CHANGELOG | 中 |
| 文档 | 补充 CONTRIBUTING.md | 低 |

---

## 工时汇总

| 阶段 | 任务 | 原计划工时 | 调整后工时 |
|------|------|------------|------------|
| **阶段一** | 任务 1.1 Info.plist | 0.5h | 0.5h |
| | 任务 1.2 CLAUDE.md | 2-3h | 2-3h |
| | 任务 1.3 E2E 验收 | 未列出 | 4-8h |
| *阶段一小计* | | *未列出* | *7-12h* |
| **阶段二** | 任务 2.1 GitHub CI | 4-6h | 4-6h |
| | 任务 2.2 构建脚本 | 2-3h | 2-3h |
| | 任务 2.3 preload.js | 6-10h | 8-16h |
| | 任务 2.4 API Key | 4-6h | 4-8h（含评估） |
| *阶段二小计* | | *16-25h* | *18-33h* |
| **阶段三** | 任务 3.1 签名公证 | 8-16h | 16-24h |
| | 任务 3.2 Swift 6 | 9.5h | 12-20h |
| | 任务 3.3 本地流式 | 未列出 | 16-24h（可选） |
| *阶段三小计* | | *20-40h* | *44-68h（含可选）* |
| **总计（不含可选）** | | *43-77h* | *69-113h* |

---

## 执行顺序建议

| 周次 | 任务 | 备注 |
|------|------|------|
| Week 1 | 任务 1.1 + 1.2 + 1.3（E2E 验收优先） | 并行执行 |
| Week 2 | 任务 2.1 + 2.2（CI + 构建脚本） | |
| Week 3 | 任务 2.3（preload.js 拆分） | 可与 2.4 并行 |
| Week 4 | 任务 2.4（API Key 安全改造） | 先评估再实施 |
| Week 5-6 | 任务 3.1（签名公证） | 如已有 Developer ID |
| Week 7-8 | 任务 3.2（Swift 6） | 先跑评估 |
| Week 9+ | 任务 3.3（可选）+ 阶段四 | 产品优先级决定 |

---

## 关键风险与缓解

| 风险 | 等级 | 缓解措施 |
|------|------|----------|
| E2E 验收发现 P0 问题 | 高 | 第一周优先执行，问题立即修复 |
| preload.js 拆分破坏 WebView 桥接 | 中 | 拆分前后完整测试 IPC 通道 |
| API Key 改造成本过高 | 中 | 先用方案 B 过渡，分阶段收紧 |
| Swift 6 警告过多 | 中 | 用 `@preconcurrency` 过渡，不阻塞 |
| 签名公证流程不熟 | 中 | 预留 2 周学习和测试 |

---

## 验证命令

执行每阶段后，运行以下命令验证：

```bash
# 编译验证
swift build

# 测试验证
swift test

# 启动烟雾验证
swift run MouthType

# 构建验证（阶段二后）
./scripts/build.sh debug
./scripts/build.sh release
```

---

## 变更日志

| 日期 | 变更 |
|------|------|
| 2026-05-05 | 初始版本（基于 Hermes 原计划优化） |

---

## 原计划主要调整说明

1. **删除了不存在的测试套件修复任务**：实际 `swift test` 158 个测试全部通过
2. **增加了 E2E 手工验收任务**：`docs/e2e-checklist.md` 存在但未执行
3. **调整了 API Key 加固策略**：先评估成本，不强制一步到位
4. **增加了 Swift 6 评估步骤**：先跑 `-strict-concurrency=complete` 再决定策略
5. **调整了工时估算**：基于实际项目状态（测试已通过，无需修复）
6. **澄清了架构差异**：Swift 原生 vs Electron
