import Foundation

/// 后处理输出策略
///
/// 定义 AI 后处理的强度和风格
enum PostProcessStrategy: String, CaseIterable, Sendable {
    /// 原始优先 - 仅修正明显错误
    case rawFirst = "raw_first"

    /// 轻度润色 - 修正标点、语气词
    case lightPolish = "light_polish"

    /// 可发布 - 完整润色，适合正式场合
    case publishable = "publishable"

    /// 结构化重写 - 重组语句结构
    case structuredRewrite = "structured_rewrite"

    var displayName: String {
        switch self {
        case .rawFirst: "原始优先"
        case .lightPolish: "轻度润色"
        case .publishable: "可发布"
        case .structuredRewrite: "结构化重写"
        }
    }

    var description: String {
        switch self {
        case .rawFirst:
            return "仅修正明显错误，保留原始风格"
        case .lightPolish:
            return "修正标点、移除语气词，保持自然"
        case .publishable:
            return "完整润色，适合邮件/文档等正式场合"
        case .structuredRewrite:
            return "重组语句结构，提升逻辑性"
        }
    }

    /// 对应的 AI 处理模式
    var aiMode: AIMode {
        switch self {
        case .rawFirst:
            return .cleanup
        case .lightPolish, .publishable:
            return .rewrite
        case .structuredRewrite:
            return .rewrite
        }
    }

    /// 是否启用多轮迭代
    var enableIterations: Bool {
        switch self {
        case .rawFirst, .lightPolish:
            return false
        case .publishable, .structuredRewrite:
            return true
        }
    }

    /// 推荐迭代次数
    var recommendedIterations: Int {
        switch self {
        case .rawFirst, .lightPolish:
            return 1
        case .publishable:
            return 2
        case .structuredRewrite:
            return 3
        }
    }
}

/// 输入场景策略
///
/// 根据目标应用/场景调整后处理行为
enum InputContextStrategy: String, CaseIterable, Sendable {
    /// 聊天/即时通讯
    case chat = "chat"

    /// 邮件
    case email = "email"

    /// 文档编辑
    case document = "document"

    /// 搜索框
    case search = "search"

    /// 表单输入
    case form = "form"

    /// Markdown 编辑器
    case markdown = "markdown"

    /// 代码编辑器 (IDE)
    case ide = "ide"

    /// 社交媒体
    case social = "social"

    var displayName: String {
        switch self {
        case .chat: "聊天"
        case .email: "邮件"
        case .document: "文档"
        case .search: "搜索"
        case .form: "表单"
        case .markdown: "Markdown"
        case .ide: "代码"
        case .social: "社交媒体"
        }
    }

    /// 推荐的输出策略
    var recommendedOutputStrategy: PostProcessStrategy {
        switch self {
        case .chat, .social:
            return .lightPolish
        case .email, .document:
            return .publishable
        case .search, .form:
            return .rawFirst
        case .markdown:
            return .lightPolish
        case .ide:
            return .rawFirst
        }
    }

    /// 是否启用 Markdown 格式化
    var enableMarkdown: Bool {
        switch self {
        case .markdown, .document, .email:
            return true
        default:
            return false
        }
    }

    /// 是否保留口语化表达
    var preserveColloquialism: Bool {
        switch self {
        case .chat, .social:
            return true
        default:
            return false
        }
    }

    /// 是否自动补全标点
    var autoCompletePunctuation: Bool {
        switch self {
        case .email, .document, .markdown:
            return true
        default:
            return false
        }
    }
}

/// 术语管理配置
struct TerminologyConfig: Sendable {
    /// 热词列表（优先识别）
    var hotwords: [String] = []

    /// 黑名单（避免使用）
    var blacklist: [String] = []

    /// 同音词映射（正确写法）
    var homophoneMappings: [String: String] = [:]

    /// 组织术语表
    var glossary: [String: String] = [:]  // term -> definition/replacement

    /// 自动学习的新术语
    var learnedTerms: [String] = []

    /// 是否启用自动学习
    var enableAutoLearn: Bool = true

    /// 是否启用术语替换
    var enableReplacement: Bool = true

    init(hotwords: [String] = [],
         blacklist: [String] = [],
         homophoneMappings: [String: String] = [:],
         glossary: [String: String] = [:],
         learnedTerms: [String] = [],
         enableAutoLearn: Bool = true,
         enableReplacement: Bool = true) {
        self.hotwords = hotwords
        self.blacklist = blacklist
        self.homophoneMappings = homophoneMappings
        self.glossary = glossary
        self.learnedTerms = learnedTerms
        self.enableAutoLearn = enableAutoLearn
        self.enableReplacement = enableReplacement
    }
}

/// 后处理策略配置
struct PostProcessConfig: Sendable {
    /// 输出策略
    var outputStrategy: PostProcessStrategy = .lightPolish

    /// 输入场景
    var inputContext: InputContextStrategy = .chat

    /// 术语配置
    var terminology: TerminologyConfig = TerminologyConfig()

    /// 是否启用 AI 后处理
    var enableAI: Bool = true

    /// 是否启用自动迭代
    var enableAutoIterate: Bool = false

    /// 迭代次数
    var iterations: Int = 1

    init(outputStrategy: PostProcessStrategy = .lightPolish,
         inputContext: InputContextStrategy = .chat,
         terminology: TerminologyConfig = TerminologyConfig(),
         enableAI: Bool = true,
         enableAutoIterate: Bool = false,
         iterations: Int = 1) {
        self.outputStrategy = outputStrategy
        self.inputContext = inputContext
        self.terminology = terminology
        self.enableAI = enableAI
        self.enableAutoIterate = enableAutoIterate
        self.iterations = iterations
    }
}
