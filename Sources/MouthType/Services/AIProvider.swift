import Foundation
import os

private let aiProviderLog = Logger(subsystem: "com.mouthtype", category: "AIProvider")

// MARK: - 处理结果

/// AI 处理结果（避免与 ProcessResult.swift 冲突）
struct AIProcessResult: Sendable {
    var text: String
    var provider: String
    var model: String
    var processingTimeMs: Int
    var overlapScore: Double?  // 重叠分数（质量校验）
    var strictModePassed: Bool  // 严格模式验证结果
    var isAgentCommand: Bool
}

// MARK: - 处理选项

struct ProcessOptions: Sendable {
    var systemPrompt: String
    var model: String
    var temperature: Double
    var maxTokens: Int
    var strictMode: Bool  // 严格模式验证
    var timeout: TimeInterval

    static let `default` = ProcessOptions(
        systemPrompt: "你是专业的语音听写后处理助手。",
        model: "qwen-plus",
        temperature: 0.3,
        maxTokens: 500,
        strictMode: true,
        timeout: 30
    )
}

// MARK: - AIProvider 协议

protocol AIProvider: Sendable {
    var providerId: String { get }
    var displayName: String { get }

    func process(
        text: String,
        options: ProcessOptions
    ) async throws -> AIProcessResult

    func validateAPIKey(_ key: String) async throws -> Bool
    var isAvailable: Bool { get }
}

// MARK: - 严格模式验证（Mouthpiece 模式）

struct StrictModeValidator: Sendable {
    /// Answer-like 模式检测（防止 LLM 返回解释性内容）
    private let answerPatterns: [String] = [
        "答案",
        "根据",
        "总结",
        "综上所述",
        "我们可以",
        "总而言之",
        "总之",
        "以上",
        "如下",
        "值得注意的是",
    ]

    /// 重叠分数阈值
    let minOverlapScore: Double

    init(minOverlapScore: Double = 0.3) {
        self.minOverlapScore = minOverlapScore
    }

    /// 验证输出是否通过严格模式
    func validate(output: String, originalText: String) -> (passed: Bool, overlapScore: Double) {
        let overlapScore = calculateOverlapScore(original: originalText, processed: output)
        let answerLikeDetected = containsAnswerPattern(output)

        aiProviderLog.debug("[StrictMode] overlapScore=\(overlapScore, privacy: .public), answerLikeDetected=\(answerLikeDetected, privacy: .public)")

        if answerLikeDetected {
            aiProviderLog.warning("[StrictMode] 检测到 answer-like 模式")
            return (false, overlapScore)
        }

        if overlapScore < minOverlapScore {
            aiProviderLog.warning("[StrictMode] 重叠分数过低：\(overlapScore)")
            return (false, overlapScore)
        }

        return (true, overlapScore)
    }

    /// 检测 answer-like 模式
    private func containsAnswerPattern(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        for pattern in answerPatterns {
            if lowercased.contains(pattern.lowercased()) {
                return true
            }
        }
        return false
    }

    /// 计算重叠分数（Jaccard similarity）
    private func calculateOverlapScore(original: String, processed: String) -> Double {
        // 简单的字符级重叠计算（中文友好）
        let originalChars = Set(original.lowercased())
        let processedChars = Set(processed.lowercased())

        let intersection = originalChars.intersection(processedChars)
        let union = originalChars.union(processedChars)

        guard !union.isEmpty else { return 0 }
        return Double(intersection.count) / Double(union.count)
    }
}

// MARK: - 通用 HTTP AI Provider 基类

/// 基于 HTTP POST 的 AI Provider 通用实现
/// 复用 Bailian、OpenAI 等提供者的共同逻辑
@MainActor
class BaseHTTPIAIProvider: AIProvider {
    var providerId: String { "base" }
    var displayName: String { "Base Provider" }

    private let strictModeValidator = StrictModeValidator()

    /// API 密钥（子类重写）
    var apiKey: String { "" }

    /// 请求端点 URL（子类重写）
    var endpointURL: URL? { nil }

    /// 是否持有 API Key（子类重写）
    func hasAPIKey() -> Bool { false }

    /// 构建请求载荷（子类可重写）
    func buildPayload(text: String, options: ProcessOptions) -> [String: Any] {
        [
            "model": options.model,
            "messages": [
                ["role": "system", "content": options.systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": options.temperature,
            "max_tokens": options.maxTokens
        ]
    }

    /// 从响应中提取文本（子类可重写）
    func extractText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func process(text: String, options: ProcessOptions) async throws -> AIProcessResult {
        guard isAvailable else {
            throw AIError.notConfigured
        }

        guard let endpoint = endpointURL else {
            throw AIError.invalidEndpoint
        }

        let startTime = Date()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = options.timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: buildPayload(text: text, options: options))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.connectionFailed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIError.requestFailed(httpResponse.statusCode)
        }

        let resultText = try extractText(from: data)
        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)

        // 严格模式验证
        let strictValidation = strictModeValidator.validate(output: resultText, originalText: text)

        aiProviderLog.info("""
        [\(self.providerId)] 处理完成：
        - processingTime=\(processingTime)ms
        - inputLength=\(text.count)
        - outputLength=\(resultText.count)
        - strictModePassed=\(strictValidation.passed)
        - overlapScore=\(strictValidation.overlapScore)
        """)

        return AIProcessResult(
            text: resultText,
            provider: self.providerId,
            model: options.model,
            processingTimeMs: processingTime,
            overlapScore: strictValidation.overlapScore,
            strictModePassed: strictValidation.passed,
            isAgentCommand: false
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        return true
    }

    var isAvailable: Bool {
        hasAPIKey() && endpointURL != nil
    }
}

// MARK: - BailianProvider 实现

/// Thread safety: Designed for async/await usage with proper isolation
final class BailianProvider: BaseHTTPIAIProvider, @unchecked Sendable {
    override var providerId: String { "bailian" }
    override var displayName: String { "阿里云百炼" }

    private let settings: AppSettings

    override var apiKey: String { settings.bailianApiKey }
    override var endpointURL: URL? { settings.aiChatCompletionsURL }

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    override func hasAPIKey() -> Bool {
        !settings.bailianApiKey.isEmpty
    }

    override func validateAPIKey(_ key: String) async throws -> Bool {
        // TODO: 调用 Bailian API 验证
        return true
    }
}

// MARK: - OpenAIProvider 实现（兼容模式）

final class OpenAIProvider: BaseHTTPIAIProvider {
    override var providerId: String { "openai" }
    override var displayName: String { "OpenAI" }

    private let settings: AppSettings
    private let baseURL: String

    override var apiKey: String { settings.aiApiKey }

    override var endpointURL: URL {
        URL(string: baseURL)!.appendingPathComponent("chat").appendingPathComponent("completions")
    }

    init(
        settings: AppSettings = .shared,
        baseURL: String? = nil
    ) {
        self.settings = settings
        self.baseURL = baseURL ?? "https://api.openai.com/v1"
    }

    override func hasAPIKey() -> Bool {
        !settings.aiApiKey.isEmpty
    }

    override func validateAPIKey(_ key: String) async throws -> Bool {
        // TODO: 调用 OpenAI API 验证 (GET /v1/models)
        return true
    }
}

// MARK: - MiniMaxProvider 实现（OpenAI 兼容格式）

final class MiniMaxProvider: AIProvider {
    let providerId = "minimax"
    let displayName = "MiniMax"

    private let settings: AppSettings
    private let baseURL: String
    private let strictModeValidator = StrictModeValidator()

    init(
        settings: AppSettings = .shared,
        baseURL: String? = nil
    ) {
        self.settings = settings
        self.baseURL = baseURL ?? "https://api.minimax.chat/v1"
    }

    var isAvailable: Bool {
        hasAPIKey() && URL(string: baseURL) != nil
    }

    private func hasAPIKey() -> Bool {
        // MiniMax API key 存储在 aiApiKey 中（与 OpenAI 共享）
        !settings.aiApiKey.isEmpty
    }

    private var completionsURL: URL {
        URL(string: baseURL)!.appendingPathComponent("chat").appendingPathComponent("completions")
    }

    func process(text: String, options: ProcessOptions) async throws -> AIProcessResult {
        guard isAvailable else {
            throw AIError.notConfigured
        }

        let apiKey = settings.aiApiKey
        let startTime = Date()

        let payload: [String: Any] = [
            "model": options.model,
            "messages": [
                ["role": "system", "content": options.systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": options.temperature,
            "max_tokens": options.maxTokens
        ]

        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = options.timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.connectionFailed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIError.requestFailed(httpResponse.statusCode)
        }

        let resultText = try extractText(from: data)
        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)

        // 严格模式验证
        let strictValidation = strictModeValidator.validate(output: resultText, originalText: text)

        aiProviderLog.info("""
        [MiniMaxProvider] 处理完成：
        - processingTime=\(processingTime)ms
        - inputLength=\(text.count)
        - outputLength=\(resultText.count)
        - strictModePassed=\(strictValidation.passed)
        - overlapScore=\(strictValidation.overlapScore)
        """)

        return AIProcessResult(
            text: resultText,
            provider: providerId,
            model: options.model,
            processingTimeMs: processingTime,
            overlapScore: strictValidation.overlapScore,
            strictModePassed: strictValidation.passed,
            isAgentCommand: false
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        return true
    }

    private func extractText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ZhipuProvider 实现（OpenAI 兼容格式）

final class ZhipuProvider: AIProvider {
    let providerId = "zhipu"
    let displayName = "智谱 AI"

    private let settings: AppSettings
    private let baseURL: String
    private let strictModeValidator = StrictModeValidator()

    init(
        settings: AppSettings = .shared,
        baseURL: String? = nil
    ) {
        self.settings = settings
        self.baseURL = baseURL ?? "https://open.bigmodel.cn/api/paas/v4"
    }

    var isAvailable: Bool {
        hasAPIKey() && URL(string: baseURL) != nil
    }

    private func hasAPIKey() -> Bool {
        // Zhipu API key 存储在 aiApiKey 中（与 OpenAI 共享）
        !settings.aiApiKey.isEmpty
    }

    private var completionsURL: URL {
        URL(string: baseURL)!.appendingPathComponent("chat").appendingPathComponent("completions")
    }

    func process(text: String, options: ProcessOptions) async throws -> AIProcessResult {
        guard isAvailable else {
            throw AIError.notConfigured
        }

        let apiKey = settings.aiApiKey
        let startTime = Date()

        let payload: [String: Any] = [
            "model": options.model,
            "messages": [
                ["role": "system", "content": options.systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": options.temperature,
            "max_tokens": options.maxTokens
        ]

        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = options.timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.connectionFailed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIError.requestFailed(httpResponse.statusCode)
        }

        let resultText = try extractText(from: data)
        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)

        // 严格模式验证
        let strictValidation = strictModeValidator.validate(output: resultText, originalText: text)

        aiProviderLog.info("""
        [ZhipuProvider] 处理完成：
        - processingTime=\(processingTime)ms
        - inputLength=\(text.count)
        - outputLength=\(resultText.count)
        - strictModePassed=\(strictValidation.passed)
        - overlapScore=\(strictValidation.overlapScore)
        """)

        return AIProcessResult(
            text: resultText,
            provider: providerId,
            model: options.model,
            processingTimeMs: processingTime,
            overlapScore: strictValidation.overlapScore,
            strictModePassed: strictValidation.passed,
            isAgentCommand: false
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        return true
    }

    private func extractText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - FallbackAIProvider（责任链模式）

final class FallbackAIProvider: AIProvider {
    let providerId = "fallback_chain"
    let displayName = "智能 fallback 链"

    private let providers: [AIProvider]
    private let strictModeValidator = StrictModeValidator()

    init(providers: [AIProvider]) {
        self.providers = providers
    }

    var isAvailable: Bool {
        providers.contains { $0.isAvailable }
    }

    func process(text: String, options: ProcessOptions) async throws -> AIProcessResult {
        var lastError: Swift.Error?
        var lastResult: AIProcessResult?

        // 按顺序尝试各 Provider
        for provider in providers {
            aiProviderLog.debug("[FallbackAIProvider] 尝试 provider: \(provider.providerId)")

            guard provider.isAvailable else {
                aiProviderLog.debug("[FallbackAIProvider] \(provider.providerId) 不可用，跳过")
                continue
            }

            do {
                let result = try await provider.process(text: text, options: options)

                // 验证结果质量
                if result.strictModePassed && (result.overlapScore ?? 0) >= strictModeValidator.minOverlapScore {
                    aiProviderLog.info("[FallbackAIProvider] \(provider.providerId) 成功，overlapScore=\(result.overlapScore ?? 0)")
                    return result
                }

                // 质量不达标，保存结果继续尝试下一个
                aiProviderLog.warning("[FallbackAIProvider] \(provider.providerId) 质量不达标，继续尝试下一个")
                lastResult = result

            } catch {
                lastError = error
                aiProviderLog.error("[FallbackAIProvider] \(provider.providerId) 失败：\(error.localizedDescription)")
                continue
            }
        }

        // 所有 Provider 都失败，返回最后一个结果（如果有）
        if let lastResult = lastResult {
            aiProviderLog.warning("[FallbackAIProvider] 所有 provider 质量不达标，返回最佳结果")
            return lastResult
        }

        throw lastError ?? AIError.allProvidersFailed
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        return true
    }
}

// MARK: - 向后兼容的封装（保留原有 API）

struct AIResult {
    let text: String
    let isAgentCommand: Bool
}

// MARK: - AI Provider 类型枚举

/// AI Provider 配置（占位结构，用于保持编译通过）
struct AIProviderConfig {
    var modelName: String
    var endpoint: String
    var enabled: Bool
}

/// UI 测试配置（占位结构，用于保持编译通过）
struct UITestConfiguration {
    static let current = UITestConfiguration()
    var isEnabled: Bool = false
    var isModelDownloaded: Bool = false
    var isModelDownloading: Bool = false
    var modelDownloadProgress: Double?
    var shouldShowFloatingCapsuleWindow: Bool = false
    var shouldCreateStatusItem: Bool = false
    var shouldInstallHotkeyMonitor: Bool = false
    var shouldShowOnboarding: Bool = false
    var currentModelSizeText: String = ""
    var accessibilityGranted: Bool = false
    var inputMonitoringGranted: Bool = false
    var currentProviderDisplayName: String = ""
    var currentModelName: String = ""
    var currentModelPath: String = ""
    var capsuleText: String = ""
    var capsuleStatusLabel: String = ""
    var shouldShowCapsuleAudioLevel: Bool = false

    func applyLaunchState(to appState: any Sendable) {}
}

/// 进程运行器（占位结构，用于保持编译通过）
struct ProcessRunner {
    static func run(url: URL, arguments: [String]) async throws -> ProcessResult {
        fatalError("ProcessRunner not implemented")
    }
}

enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    // 国内可用 Provider
    case bailian = "bailian"
    case minimax = "minimax"
    case zhipu = "zhipu"

    // 保留但隐藏（国内网络不可用）
    case openai = "openai"
    case anthropic = "anthropic"

    // 容错模式
    case fallback = "fallback_chain"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bailian: "阿里云百炼"
        case .minimax: "MiniMax"
        case .zhipu: "智谱 AI"
        case .openai: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        case .fallback: "智能 Fallback 链"
        }
    }

    var description: String {
        switch self {
        case .bailian: "阿里云百炼 Qwen 模型，中文优化"
        case .minimax: "MiniMax 海螺 AI，高性价比"
        case .zhipu: "智谱 GLM 模型，学术场景优化"
        case .openai: "OpenAI 或兼容 API（支持自定义 BaseURL）"
        case .anthropic: "Anthropic Claude 系列模型"
        case .fallback: "按顺序尝试多个 Provider，自动容错"
        }
    }

    /// 是否为国内可用 Provider（用于 UI 过滤）
    var isDomesticAvailable: Bool {
        switch self {
        case .bailian, .minimax, .zhipu:
            return true
        case .openai, .anthropic, .fallback:
            return false
        }
    }
}

enum AIMode: String, CaseIterable, Identifiable {
    case cleanup
    case rewrite
    case agentCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cleanup: "文本清理"
        case .rewrite: "风格改写"
        case .agentCommand: "Agent 指令"
        }
    }
}

/// 向后兼容的 BailianAIProvider（保留原有接口）
///
/// Thread safety: Designed for async/await usage with proper isolation
final class BailianAIProvider: @unchecked Sendable {
    private let settings: AppSettings
    private let bailianProvider: BailianProvider

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.bailianProvider = BailianProvider(settings: settings)
    }

    var isAvailable: Bool {
        bailianProvider.isAvailable
    }

    func process(text: String, mode: AIMode, agentName: String) async throws -> AIResult {
        let options = ProcessOptions(
            systemPrompt: systemPrompt(for: mode, agentName: agentName),
            model: settings.aiModelName,
            temperature: 0.3,
            maxTokens: 500,
            strictMode: false,  // 兼容模式禁用严格验证
            timeout: 30
        )

        let result = try await bailianProvider.process(text: text, options: options)
        return AIResult(text: result.text, isAgentCommand: mode == .agentCommand)
    }

    func processIterative(text: String, agentName: String, iterations: Int) async throws -> AIResult {
        var currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pipeline: [AIMode]

        if iterations == 1 {
            pipeline = [.cleanup]
        } else if iterations == 2 {
            pipeline = [.cleanup, .rewrite]
        } else {
            pipeline = [.cleanup, .rewrite, .cleanup]
        }

        for (index, mode) in pipeline.enumerated() {
            do {
                let result = try await process(text: currentText, mode: mode, agentName: agentName)
                currentText = result.text

                if index == pipeline.count - 1 {
                    return AIResult(text: currentText, isAgentCommand: result.isAgentCommand)
                }
            } catch {
                if index == 0 {
                    throw error
                }
                return AIResult(text: currentText, isAgentCommand: false)
            }
        }

        return AIResult(text: currentText, isAgentCommand: false)
    }

    private func systemPrompt(for mode: AIMode, agentName: String) -> String {
        switch mode {
        case .cleanup:
            return "你是一个文本后处理助手。修正语音转写结果中的标点、去除语气词、整理格式。使用简体中文输出，不要使用繁体字。只输出处理后的文本，不要解释。"
        case .rewrite:
            return "你是一个文本改写助手。改写以下语音转写文本使其更加通顺、正式。使用简体中文输出，不要使用繁体字。只输出改写后的文本，不要解释。"
        case .agentCommand:
            return "你是\(agentName)，一个 AI 助手。根据用户的语音指令执行操作，只输出结果文本。使用简体中文输出。"
        }
    }
}

// MARK: - 错误类型

enum AIError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case connectionFailed
    case requestFailed(Int)
    case invalidResponse
    case iterationFailed
    case allProvidersFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "AI 未配置（需要 API Key 和请求地址）"
        case .invalidEndpoint: "AI 请求地址无效"
        case .connectionFailed: "AI 服务连接失败"
        case .requestFailed(let code): "AI 请求失败（\(code)）"
        case .invalidResponse: "AI 返回了无法解析的结果"
        case .iterationFailed: "AI 迭代优化失败"
        case .allProvidersFailed: "所有 AI Provider 均失败"
        }
    }
}

// MARK: - AIProviderType 扩展（默认配置）

extension AIProviderType {
    /// 获取默认配置
    var defaultConfig: AIProviderConfig {
        switch self {
        case .bailian:
            return AIProviderConfig(
                modelName: "qwen-plus",
                endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                enabled: false
            )
        case .minimax:
            return AIProviderConfig(
                modelName: "MiniMax-Text-01",
                endpoint: "https://api.minimax.chat/v1",
                enabled: false
            )
        case .zhipu:
            return AIProviderConfig(
                modelName: "glm-4",
                endpoint: "https://open.bigmodel.cn/api/paas/v4",
                enabled: false
            )
        case .openai:
            return AIProviderConfig(
                modelName: "gpt-4o",
                endpoint: "https://api.openai.com/v1",
                enabled: false
            )
        case .anthropic:
            return AIProviderConfig(
                modelName: "claude-sonnet-4-0",
                endpoint: "https://api.anthropic.com",
                enabled: false
            )
        case .fallback:
            return AIProviderConfig(
                modelName: "",
                endpoint: "",
                enabled: false
            )
        }
    }
}
