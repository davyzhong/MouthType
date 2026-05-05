# MouthType / OpenWhispr 项目分析报告 & 优化方案

> 报告生成时间：2025-05-05
> 分析范围：MouthType Swift macOS 应用（含 preload.js WebView 桥接层）
> 状态：初始版本

---

## 一、项目概况

| 指标 | 数值 |
|------|------|
| 定位 | macOS 原生语音输入应用（Swift SPM） |
| 实际技术栈 | Swift + SwiftUI + WebKit WebView（非 Electron） |
| 总文件数 | 86 个（不含 .git/.build） |
| 总 LOC | ~20,800 行（Swift 12,050 + Markdown 7,980 + 其他） |
| 总大小 | ~918 MB（含 ML 模型 639 MB） |
| 外部依赖 | 仅 SQLite.swift 0.16.0 |
| 最低平台 | macOS 14 (Sonoma) |
| 版本 | 0.1.0 (build 1) |

### 目录结构

```
MouthType/
├── Sources/MouthType/          # 主源码（10,284 LOC）
│   ├── Services/               # 5,053 LOC（42%）-- ASR、音频、VAD、插入
│   ├── UI/                     # 2,399 LOC（20%）-- SwiftUI 界面
│   ├── Platform/               # 1,811 LOC（15%）-- 平台适配
│   ├── Models/                 #   715 LOC（6%）-- 数据模型
│   └── Utilities/              #   106 LOC（1%）-- 工具
├── Tests/MouthTypeTests/       # 1,458 LOC -- 6 个测试文件
├── preload.js                  # 448 LOC -- WebView 桥接（唯一 JS 文件）
├── Resources/                  # 639 MB -- ML 模型 + 配置
├── docs/                       # ~7,980 LOC -- 详细文档
└── scripts/                    # 2 个构建脚本
```

### 重要说明

CLAUDE.md 描述的是 Electron 架构（main.js、src/helpers/、React 组件），但**实际仓库是 Swift macOS 原生应用**。CLAUDE.md 与实际代码存在严重不一致，这是本次 Review 发现的最优先问题之一。

---

## 二、优势亮点

### 2.1 极简依赖
仅一个外部依赖（SQLite.swift），极大降低了供应链风险和维护负担。所有核心功能（音频采集、ASR、VAD、UI）均为手写。

### 2.2 服务层设计扎实
Services 层占 42% 的代码量，覆盖了多个 ASR 后端（Whisper、百炼、Paraformer、SenseVoice），音频预处理、VAD 语音活动检测、文本后处理和插入逻辑。架构上支持多 provider 切换。

### 2.3 文档丰富
7,980 行 Markdown，包含从 Phase 2 到 Phase 7 的详细实现报告、设计文档、QA 测试矩阵和发布检查清单。这在同类项目中很少见。

### 2.4 构建干净
`swift build` 和 `swift build -c release` 均通过，仅 1 个 Sendable 警告，无编译错误。

### 2.5 preload.js 设计合理
registerListener helper 模式避免了事件监听器泄漏，清理函数设计合理。

---

## 三、关键问题（按优先级）

### P0: 测试套件编译失败

**严重程度：高**

`swift test` 无法通过编译。AppSettingsTests.swift 存在两类错误：

1. 尝试写入只读计算属性 `audioLevel`（无 setter）
2. 在非隔离上下文调用 `@MainActor` 方法 `state.transition(to:)`，缺少 `await`

README 声称"170+ 测试用例、>80% 覆盖率"与实际不符。这是一个可信度问题——测试覆盖声明无法被验证。

**修复方案**：
```swift
// 问题1：audioLevel 是只读属性，需要在 AppState 内部提供测试用的 setter
// 或改用 dependency injection 方式注入 AppState

// 问题2：actor isolation 错误
// 所有调用 @MainActor 方法的测试需要包装在 Task { @MainActor in ... } 中
// 或使用 XCTUnwrap 等 MainActor-annotated 测试工具
```

### P1: 零 CI/CD

**严重程度：高**

无 GitHub Actions、无 Makefile、无 Fastlane、无任何自动化构建/测试流水线。每次合并都是未经验证的。

### P2: 无分发签名

**严重程度：中**

仅有 ad-hoc codesign（`codesign --sign -`），无 Apple Developer ID 签名、无公证（notarization）。无法向用户分发。

### P3: CLAUDE.md 与实际代码严重不一致

**严重程度：高**

CLAUDE.md 描述的是完整的 Electron 架构，但实际仓库是 Swift macOS 原生应用。仅 preload.js 与 Electron 的 WebView 有关联。这会严重误导 AI 辅助开发。

---

## 四、代码质量问题

### 4.1 preload.js（唯一 JS 文件，448 行）

| 维度 | 评级 | 说明 |
|------|------|------|
| 组织结构 | B | 分段清晰但过于庞大（100+ IPC 通道） |
| 错误处理 | C- | 仅 1 处 try/catch，所有错误推给 renderer |
| 安全性 | C | API key 通过 IPC 暴露，openExternal 无 URL 校验 |
| 风格一致性 | B+ | 命名和格式基本统一 |

**具体问题清单**：

| # | 问题 | 严重度 | 位置 |
|---|------|--------|------|
| 1 | ~100+ IPC 通道，攻击面过大 | 高 | 全文件 |
| 2 | sendSync 阻塞 renderer 初始化 | 高 | 第 15 行 |
| 3 | 20+ 个 getter 暴露 API key 给 renderer | 高 | 第 46-150 行 |
| 4 | openExternal(url) 无 URL 白名单 | 中 | 第 197 行 |
| 5 | proxyRuntimeApiRequest 通用代理无校验 | 高 | 第 46 行 |
| 6 | ipcRenderer.send() fire-and-forget 无确认 | 中 | 第 71, 319-320, 344-345, 368-369, 396-397, 443 行 |
| 7 | 事件监听模式不统一（registerListener vs 手动） | 低 | 全文件 |
| 8 | 无 JSDoc / TypeScript 类型注解 | 低 | 全文件 |

### 4.2 Swift 源码

**Services 层（5,053 LOC）**：架构清晰，provider 模式设计良好。需关注的是 actor isolation（Swift 6 兼容性）和错误传播链。

**UI 层（2,399 LOC）**：SwiftUI 使用得当，无明显问题。

**Platform 层（1,811 LOC）**：平台适配代码需在多版本 macOS 上持续回归测试。

**Models 层（715 LOC）**：需确认 AppSettingsTests 中引用的属性变更是否同步更新了测试。

---

## 五、安全审计

| 风险 | 等级 | 详情 |
|------|------|------|
| API Key 暴露 | 高 | preload.js 的 20+ 个 getter 将密钥传给 renderer |
| SSRF（proxyRuntimeApiRequest） | 高 | 通用 HTTP 代理无目的地白名单 |
| openExternal 无校验 | 中 | 可打开任意 URL |
| IPC 无输入验证 | 中 | 所有关键函数参数无类型/边界检查 |
| sendSync 阻塞 | 低 | 性能问题而非安全 |

---

## 六、构建与发布评分

| 维度 | 评分 | 说明 |
|------|------|------|
| Package.swift | 7/10 | 干净简洁，unsafe flags 对独立 App 可接受 |
| 构建脚本 | 6/10 | 两套脚本重复逻辑，release 脚本会清除用户数据 |
| 测试基础设施 | 3/10 | 存在但编译失败 |
| CI/CD | 0/10 | 完全缺失 |
| 代码签名 | 4/10 | 仅本地 ad-hoc |
| 发布流程 | 3/10 | 文档引用 npm 命令（来自模板），实际不适用 |
| 依赖管理 | 9/10 | 极简且版本锁定 |
| Info.plist | 4/10 | LSUIElement=false（应为 true），双 Usage 拼写错误 |

---

## 七、优化修复计划方案

### 阶段一：止血（P0 级 — 1-2 周）

**目标**：修复一切阻止正常开发节奏的问题

#### 1.1 修复测试套件（最高优先级）

```
负责人：davyzhong
预估工时：4-8 小时
影响：恢复可信的测试覆盖
```

操作步骤：
1. 运行 `swift test` 获取完整编译错误列表
2. 修复 AppSettingsTests 中的 actor isolation 问题（将同步调用改为 Task @MainActor 包装）
3. 为 audioLevel 等只读属性添加内部测试 setter 或使用 dependency injection
4. 验证 `swift test` 零错误通过
5. 逐步恢复覆盖率到合理水平（目标 60%+）

#### 1.2 重写 CLAUDE.md

```
负责人：davyzhong
预估工时：2-3 小时
影响：AI 辅助开发准确性
```

操作步骤：
1. 删除所有 Electron 相关描述（main.js、src/helpers/、React 组件）
2. 补充 Swift/SwiftUI 架构描述
3. 补充 preload.js 作为 WebView 桥接的角色说明
4. 补充 Swift Package Manager 构建方式
5. 补充代码签名和分发注意事项

#### 1.3 修复 Info.plist 问题

```
负责人：davyzhong
预估工时：0.5 小时
```

- 将 LSUIElement 改为 true（浮动胶囊 + 菜单栏应用不应出现在 Dock）
- 修复 NSAppleEventsUsageUsageDescription 拼写错误

---

### 阶段二：工程化基础（ P1 级 — 2-4 周）

**目标**：建立 CI/CD 门禁和代码质量基线

#### 2.1 添加 GitHub Actions CI

```
文件名：.github/workflows/ci.yml
预估工时：4-6 小时
```

```yaml
# 基础流程
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
      - name: Test
        run: swift test
      - name: Ad-hoc sign
        run: codesign --force --deep --sign - .build/debug/MouthType
```

后续可扩展：
- SwiftLint / SwiftFormat 检查
- 编译警告视为错误（`-warnings-as-errors`）
- SonarCloud 代码质量扫描

#### 2.2 合并并规范化构建脚本

```
预估工时：2-3 小时
```

- 合并 build-app.sh 和 build-with-entitlements.sh 为单一 build.sh
- 引入 BUILD_MODE=debug|release 参数
- 移除 release 脚本中的用户数据清除逻辑
- 添加版本号注入（从 git tag 或 Info.plist 读取）

#### 2.3 preload.js 模块化拆分

```
预估工时：6-10 小时
```

将 448 行的 preload.js 按域拆分：

```
preload/
├── index.js         # 聚合导出
├── keys.js          # API key get/set（~20 通道）
├── streaming.js     # 流式 ASR（~40 通道）
├── models.js        # 模型管理（~15 通道）
├── window.js        # 窗口控制（~15 通道）
├── database.js      # 数据库 CRUD（~10 通道）
└── system.js        # 系统/剪贴板/热键（~20 通道）
```

同时：
- 统一所有事件监听通过 registerListener helper
- 为关键函数添加 JSDoc 类型注释
- 在 main process 添加 URL 白名单校验（openExternal、proxyRuntimeApiRequest）

#### 2.4 API Key 安全加固

```
预估工时：4-6 小时
```

方案选择（按优先级）：

**方案 A（推荐）**：不将 key 暴露给 renderer
- renderer 通过 IPC 发请求
- main process 执行实际 API 调用
- renderer 永远拿不到 raw key

**方案 B**：如果必须暴露 key
- 改为只在需要时通过一次性 token 获取
- 添加 IPC 通道的权限分级

---

### 阶段三：质量提升（ P2 级 — 4-8 周）

**目标**：提升代码质量和可维护性

#### 3.1 分发签名与公证

```
预估工时：8-16 小时（含流程测试）
```

1. 申请 Apple Developer ID（如尚未）
2. 配置签名 identity 到构建脚本
3. 添加 notarytool 公证步骤
4. 配置 Sparkle 自动更新框架（推荐）

#### 3.2 Swift 6 兼容性准备

```
预估工时：4-8 小时
```

- 在 Package.swift 中添加 `swiftLanguageVersions`
- 逐步引入 `@Sendable` 标注
- 检查所有 actor boundary 是否正确
- 使用 `-strict-concurrency=complete` 编译验证

#### 3.3 测试覆盖率恢复与扩展

```
预估工时：8-16 小时
```

1. 修复阶段一后已有基础
2. 补充 Services 层集成测试
3. 补充 UI 层 snapshot 测试（swift-snapshot-testing）
4. 配置 codecov 或 coveralls 集成

#### 3.4 前端正本清源（如有前端部分）

```
说明：CLAUDE.md 提及的 React 前端不在本仓库
如后续存在，需处理：
```

- 统一 localStorage 和 Zustand store 状态源
- 迁移 useAudioRecording.js → TypeScript
- 拆分 SettingsPage.tsx（1,492 行 → 多文件）
- 为 window.electronAPI 创建类型化 facade
- 补充 DictationCapsule aria-label

---

### 阶段四：持续改进（长期）

#### 4.1 监控与可观测性
- 添加崩溃报告（sentry 或 crashlytics）
- 添加启动性能埋点
- 添加 ASR 质量埋点

#### 4.2 性能优化
- Instruments 分析启动时间
- 内存 profile（特别是 ASR 服务）
- SwiftUI 视图懒加载优化

#### 4.3 文档维护
- 每次发布生成 CHANGELOG.md
- 更新架构图（当前已过期）
- 补充贡献指南（CONTRIBUTING.md）

---

## 八、工时汇总

| 阶段 | 任务 | 预估工时 |
|------|------|----------|
| **阶段一** | 修复测试套件 | 4-8h |
| | 重写 CLAUDE.md | 2-3h |
| | 修复 Info.plist | 0.5h |
| *阶段一小计* | | *7-12h* |
| **阶段二** | GitHub Actions CI | 4-6h |
| | 合并构建脚本 | 2-3h |
| | preload.js 模块化 | 6-10h |
| | API Key 安全加固 | 4-6h |
| *阶段二小计* | | *16-25h* |
| **阶段三** | 分发签名与公证 | 8-16h |
| | Swift 6 兼容性 | 4-8h |
| | 测试覆盖率恢复 | 8-16h |
| *阶段三小计* | | *20-40h* |
| **阶段四** | 监控/性能/文档 | 持续 |
| **总计（阶段一至三）** | | **43-77h** |

---

## 九、附录

### A. 当前已知编译错误（swift test）

```
AppSettingsTests.swift:
- Line 203: audioLevel 是只读属性，无法外部赋值
- Lines 206-267+: @MainActor 方法从非隔离上下文同步调用
```

### B. 文档引用错误清单

| 文档 | 错误内容 | 修复方向 |
|------|----------|----------|
| CLAUDE.md | 描述 Electron 架构 | 重写为 Swift 原生架构 |
| docs/release/asr-quality-checklist.md | 引用 `npm run` 命令 | 替换为 `swift build` 等效命令 |

### C. Info.plist 问题

- `NSAppleEventsUsageUsageDescription` — 双 Usage 拼写错误
- `LSUIElement = false` — 浮动胶囊应用应为 true

### D. 推荐工具链

| 用途 | 工具 |
|------|------|
| CI/CD | GitHub Actions |
| 代码格式 | SwiftFormat |
| 代码检查 | SwiftLint |
| 覆盖率 | XcodeCoverage + codecov |
| 自动更新 | Sparkle |
| 崩溃报告 | Sentry |
| 依赖管理 | Swift Package Manager（已使用）|
