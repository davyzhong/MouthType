import Foundation

/// 插入意图类型
///
/// 定义文本插入的目标行为
enum InsertionIntent: Sendable {
    /// 插入 - 在光标位置插入文本
    case insert

    /// 替换选中 - 替换当前选中的文本
    case replaceSelection

    /// 追加 - 在当前内容后追加文本
    case appendAfterSelection

    /// 智能 - 根据上下文自动选择
    case smart

    var displayName: String {
        switch self {
        case .insert: "插入"
        case .replaceSelection: "替换选中"
        case .appendAfterSelection: "追加"
        case .smart: "智能"
        }
    }

    var description: String {
        switch self {
        case .insert:
            return "在光标位置插入文本"
        case .replaceSelection:
            return "替换当前选中的文本"
        case .appendAfterSelection:
            return "在当前内容后追加文本"
        case .smart:
            return "根据上下文自动选择插入方式"
        }
    }
}

/// 插入结果模式
///
/// 记录插入操作的实际执行结果
enum InsertionOutcomeMode: Sendable {
    /// 成功插入
    case inserted

    /// 成功替换
    case replaced

    /// 成功追加
    case appended

    /// 仅复制到剪贴板
    case copied

    /// 失败
    case failed(reason: String)

    var isSuccess: Bool {
        switch self {
        case .inserted, .replaced, .appended: true
        case .copied, .failed: false
        }
    }

    var displayName: String {
        switch self {
        case .inserted: "已插入"
        case .replaced: "已替换"
        case .appended: "已追加"
        case .copied: "已复制"
        case .failed(let reason): "失败：\(reason)"
        }
    }
}

/// 应用类型分类
///
/// 用于选择兼容性配置文件
enum AppFamily: String, Sendable {
    case browser = "browser"
    case electron = "electron"
    case native = "native"
    case terminal = "terminal"
    case ide = "ide"
    case document = "document"
    case chat = "chat"
    case unknown = "unknown"

    static func detect(appName: String) -> AppFamily {
        let lowercased = appName.lowercased()

        // IDE
        let ideApps = ["xcode", "visual studio", "intellij", "pycharm", "webstorm", "vscode", "cursor", "zed"]
        if ideApps.contains(where: { lowercased.contains($0) }) {
            return .ide
        }

        // Terminal
        let terminalApps = ["terminal", "iterm", "warp", "kitty", "alacritty", "hyper"]
        if terminalApps.contains(where: { lowercased.contains($0) }) {
            return .terminal
        }

        // Document
        let docApps = ["pages", "word", "notion", "bear", "obsidian", "typora"]
        if docApps.contains(where: { lowercased.contains($0) }) {
            return .document
        }

        // Browser
        let browserApps = ["safari", "chrome", "firefox", "arc", "edge", "brave"]
        if browserApps.contains(where: { lowercased.contains($0) }) {
            return .browser
        }

        // Chat
        let chatApps = ["wechat", "messages", "slack", "discord", "telegram", "whatsapp"]
        if chatApps.contains(where: { lowercased.contains($0) }) {
            return .chat
        }

        // Electron (catch-all for many desktop apps)
        let electronApps = ["discord", "slack", "vscode", "notion"]
        if electronApps.contains(where: { lowercased.contains($0) }) {
            return .electron
        }

        return .native
    }
}

/// 插入兼容性配置
///
/// 针对不同应用家族的插入策略
struct InsertionCompatibilityProfile: Sendable {
    /// 目标应用家族
    let appFamily: AppFamily

    /// 默认插入意图
    let defaultIntent: InsertionIntent

    /// 是否启用选中检测
    let enableSelectionDetection: Bool

    /// 是否启用智能追加
    let enableSmartAppend: Bool

    /// 重试次数
    let retryCount: Int

    /// 重试间隔（毫秒）
    let retryIntervalMs: Int

    /// 是否启用回退到复制
    let enableFallbackCopy: Bool

    /// 是否需要特殊处理
    let requiresSpecialHandling: Bool

    /// 特殊处理说明
    let specialHandlingNotes: String

    init(
        appFamily: AppFamily,
        defaultIntent: InsertionIntent = .insert,
        enableSelectionDetection: Bool = true,
        enableSmartAppend: Bool = false,
        retryCount: Int = 2,
        retryIntervalMs: Int = 100,
        enableFallbackCopy: Bool = true,
        requiresSpecialHandling: Bool = false,
        specialHandlingNotes: String = ""
    ) {
        self.appFamily = appFamily
        self.defaultIntent = defaultIntent
        self.enableSelectionDetection = enableSelectionDetection
        self.enableSmartAppend = enableSmartAppend
        self.retryCount = retryCount
        self.retryIntervalMs = retryIntervalMs
        self.enableFallbackCopy = enableFallbackCopy
        self.requiresSpecialHandling = requiresSpecialHandling
        self.specialHandlingNotes = specialHandlingNotes
    }

    /// 获取预定义的配置文件
    static func profile(for appFamily: AppFamily) -> InsertionCompatibilityProfile {
        switch appFamily {
        case .browser:
            return InsertionCompatibilityProfile(
                appFamily: .browser,
                defaultIntent: .insert,
                enableSelectionDetection: true,
                enableSmartAppend: false,
                retryCount: 3,
                enableFallbackCopy: true,
                requiresSpecialHandling: true,
                specialHandlingNotes: "需要检测 contenteditable 和 textarea"
            )

        case .electron:
            return InsertionCompatibilityProfile(
                appFamily: .electron,
                defaultIntent: .insert,
                enableSelectionDetection: true,
                retryCount: 2,
                enableFallbackCopy: true
            )

        case .terminal:
            return InsertionCompatibilityProfile(
                appFamily: .terminal,
                defaultIntent: .appendAfterSelection,
                enableSelectionDetection: false,
                enableSmartAppend: false,
                retryCount: 2,
                requiresSpecialHandling: true,
                specialHandlingNotes: "使用 Cmd+Shift+V 粘贴"
            )

        case .ide:
            return InsertionCompatibilityProfile(
                appFamily: .ide,
                defaultIntent: .replaceSelection,
                enableSelectionDetection: true,
                enableSmartAppend: false,
                retryCount: 2,
                enableFallbackCopy: true
            )

        case .document:
            return InsertionCompatibilityProfile(
                appFamily: .document,
                defaultIntent: .insert,
                enableSelectionDetection: true,
                enableSmartAppend: true,
                retryCount: 2,
                enableFallbackCopy: true
            )

        case .chat:
            return InsertionCompatibilityProfile(
                appFamily: .chat,
                defaultIntent: .insert,
                enableSelectionDetection: true,
                enableSmartAppend: false,
                retryCount: 3,
                enableFallbackCopy: true
            )

        default:
            return InsertionCompatibilityProfile(
                appFamily: .native,
                defaultIntent: .insert,
                enableSelectionDetection: true,
                retryCount: 2,
                enableFallbackCopy: true
            )
        }
    }
}

/// 插入执行计划
///
/// 定义插入操作的执行步骤
struct InsertionPlan: Sendable {
    /// 插入意图
    let intent: InsertionIntent

    /// 目标应用家族
    let appFamily: AppFamily

    /// 配置文件
    let profile: InsertionCompatibilityProfile

    /// 执行步骤
    let steps: [InsertionStep]

    /// 回退策略
    let fallbackStrategy: FallbackStrategy

    init(
        intent: InsertionIntent,
        appFamily: AppFamily,
        profile: InsertionCompatibilityProfile,
        steps: [InsertionStep] = [],
        fallbackStrategy: FallbackStrategy = .copyToClipboard
    ) {
        self.intent = intent
        self.appFamily = appFamily
        self.profile = profile
        self.steps = steps
        self.fallbackStrategy = fallbackStrategy
    }

    /// 创建执行计划
    static func create(intent: InsertionIntent, appFamily: AppFamily) -> InsertionPlan {
        let profile = InsertionCompatibilityProfile.profile(for: appFamily)

        // 根据应用家族和意图生成步骤
        let steps = InsertionStep.generateSteps(intent: intent, appFamily: appFamily, profile: profile)

        return InsertionPlan(
            intent: intent,
            appFamily: appFamily,
            profile: profile,
            steps: steps
        )
    }
}

/// 插入执行步骤
enum InsertionStep: Sendable {
    /// 检测前台应用
    case detectFrontmostApp

    /// 检测是否有选中文本
    case detectSelection

    /// 聚焦目标位置
    case focusTarget

    /// 执行粘贴 (Cmd+V)
    case pasteCommand

    /// 执行终端粘贴 (Cmd+Shift+V)
    case terminalPasteCommand

    /// 执行替换
    case replaceSelection

    /// 执行追加
    case appendCommand

    /// 等待响应
    case wait(duration: TimeInterval)

    /// 重试
    case retry(maxAttempts: Int, delay: TimeInterval)

    /// 回退到复制
    case fallbackCopy

    /// 记录结果
    case recordOutcome(InsertionOutcomeMode)

    static func generateSteps(
        intent: InsertionIntent,
        appFamily: AppFamily,
        profile: InsertionCompatibilityProfile
    ) -> [InsertionStep] {
        var steps: [InsertionStep] = []

        // 1. 检测应用
        steps.append(.detectFrontmostApp)

        // 2. 检测选中（如果启用）
        if profile.enableSelectionDetection {
            steps.append(.detectSelection)
        }

        // 3. 聚焦
        steps.append(.focusTarget)

        // 4. 根据意图和 app 家族选择粘贴方式
        if appFamily == .terminal {
            steps.append(.terminalPasteCommand)
        } else {
            switch intent {
            case .replaceSelection:
                steps.append(.replaceSelection)
            case .appendAfterSelection:
                steps.append(.appendCommand)
            default:
                steps.append(.pasteCommand)
            }
        }

        // 5. 等待
        steps.append(.wait(duration: 0.1))

        // 6. 重试
        if profile.retryCount > 1 {
            steps.append(.retry(
                maxAttempts: profile.retryCount,
                delay: TimeInterval(profile.retryIntervalMs) / 1000.0
            ))
        }

        // 7. 回退
        if profile.enableFallbackCopy {
            steps.append(.fallbackCopy)
        }

        // 8. 记录结果
        steps.append(.recordOutcome(.inserted))

        return steps
    }
}

/// 回退策略
enum FallbackStrategy: Sendable {
    /// 复制到剪贴板
    case copyToClipboard

    /// 显示手动粘贴提示
    case showManualPasteHint

    /// 记录错误
    case logError

    /// 无操作
    case none
}
