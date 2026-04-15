import Combine
import Foundation
import os

private let strategyLog = Logger(subsystem: "com.mouthtype", category: "PostProcessStrategy")

/// 策略后处理执行器
///
/// 根据配置的策略和场景执行 AI 后处理
final class PostProcessExecutor: @unchecked Sendable {
    // MARK: - Properties

    private var config: PostProcessConfig
    private let aiProvider: BailianAIProvider
    private let terminologyService: TerminologyService

    // MARK: - Initialization

    init(
        config: PostProcessConfig = PostProcessConfig(),
        aiProvider: BailianAIProvider = BailianAIProvider(),
        terminologyService: TerminologyService = TerminologyService.shared
    ) {
        self.config = config
        self.aiProvider = aiProvider
        self.terminologyService = terminologyService
    }

    // MARK: - Public API

    /// 执行后处理
    /// - Parameters:
    ///   - text: 原始转写文本
    ///   - agentName: 代理名称（用于检测命令）
    /// - Returns: 处理后的文本
    func process(_ text: String, agentName: String) async throws -> String {
        guard config.enableAI else {
            // 仅应用术语替换
            return applyTerminologyReplacement(text)
        }

        // 检测是否为代理命令
        let mode = detectMode(for: text, agentName: agentName)
        guard mode != .agentCommand else {
            // 代理命令直接处理，不应用场景策略
            let result = try await aiProvider.process(text: text, mode: .agentCommand, agentName: agentName)
            return result.text
        }

        // 根据策略执行处理
        let result: String
        if config.enableAutoIterate && config.outputStrategy.enableIterations {
            result = try await processIterative(text)
        } else {
            result = try await processSingle(text, mode: config.outputStrategy.aiMode)
        }

        // 应用术语替换
        return applyTerminologyReplacement(result)
    }

    /// 更新配置
    func updateConfig(_ newConfig: PostProcessConfig) {
        self.config = newConfig
        strategyLog.debug("Config updated: strategy=\(newConfig.outputStrategy.rawValue), context=\(newConfig.inputContext.rawValue)")
    }

    /// 添加新术语（自动学习）
    func addLearnedTerm(_ term: String) {
        guard config.terminology.enableAutoLearn else { return }
        terminologyService.addTerm(term)
        strategyLog.trace("Learned new term: \(term)")
    }

    // MARK: - Private Processing

    private func processSingle(_ text: String, mode: AIMode) async throws -> String {
        let result = try await aiProvider.process(text: text, mode: mode, agentName: config.inputContext.displayName)

        // 应用场景特定处理
        var processed = result.text
        processed = applyContextSpecificRules(processed)

        return processed
    }

    private func processIterative(_ text: String) async throws -> String {
        let iterations = max(1, min(3, config.iterations))

        // 构建迭代管道
        let pipeline: [AIMode]
        if iterations == 1 {
            pipeline = [.cleanup]
        } else if iterations == 2 {
            pipeline = [.cleanup, .rewrite]
        } else {
            pipeline = [.cleanup, .rewrite, .cleanup]
        }

        var currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for (index, mode) in pipeline.enumerated() {
            let result = try await aiProvider.process(text: currentText, mode: mode, agentName: config.inputContext.displayName)
            currentText = result.text

            strategyLog.trace("Iteration \(index + 1)/\(pipeline.count): \"\(currentText.prefix(50))...\"")
        }

        return currentText
    }

    private func applyContextSpecificRules(_ text: String) -> String {
        var result = text

        // Markdown 格式化
        if config.inputContext.enableMarkdown {
            result = formatMarkdown(result)
        }

        // 标点补全
        if config.inputContext.autoCompletePunctuation {
            result = autoCompletePunctuation(result)
        }

        // 保留口语化（不移除）
        if !config.inputContext.preserveColloquialism {
            // 已经在 AI 处理中完成
        }

        return result
    }

    private func applyTerminologyReplacement(_ text: String) -> String {
        guard config.terminology.enableReplacement else { return text }

        var result = text

        // 同音词替换
        for (wrong, correct) in config.terminology.homophoneMappings {
            result = result.replacingOccurrences(of: wrong, with: correct, options: .caseInsensitive)
        }

        // 术语表替换
        for (term, replacement) in config.terminology.glossary {
            result = result.replacingOccurrences(of: term, with: replacement, options: .caseInsensitive)
        }

        return result
    }

    private func formatMarkdown(_ text: String) -> String {
        var result = text

        // 粗体：**text**
        // 斜体：*text*
        // 列表：- item
        // 代码：`code`

        // 简单实现：确保段落间有空行
        result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")

        return result
    }

    private func autoCompletePunctuation(_ text: String) -> String {
        var result = text

        // 句末补全标点
        if !result.isEmpty {
            let lastChar = result.last!
            if !".!?。！？".contains(lastChar) {
                result += "。"
            }
        }

        return result
    }

    private func detectMode(for text: String, agentName: String) -> AIMode {
        let lowercased = text.lowercased()
        let heyPrefixes = ["hey ", "嘿 "]

        for prefix in heyPrefixes {
            if lowercased.hasPrefix(prefix) {
                let remainder = String(text.dropFirst(prefix.count))
                if remainder.hasPrefix(agentName) {
                    return .agentCommand
                }
            }
        }

        return .cleanup
    }
}

/// 术语服务
///
/// 管理热词、黑名单、学习术语
final class TerminologyService: ObservableObject {
    static let shared = TerminologyService()

    private let queue = DispatchQueue(label: "com.mouthtype.terminology", attributes: .concurrent)
    @Published private var terms: Set<String> = []
    @Published private var hotwords: Set<String> = []
    @Published private var blacklist: Set<String> = []

    private init() {
        // 加载默认术语
        loadDefaultTerms()
    }

    // MARK: - Public API

    /// 添加术语
    func addTerm(_ term: String) {
        objectWillChange.send()
        queue.async(flags: .barrier) {
            self.terms.insert(term)
        }
    }

    /// 移除术语
    func removeTerm(_ term: String) {
        objectWillChange.send()
        queue.async(flags: .barrier) {
            self.terms.remove(term)
        }
    }

    /// 添加热词
    func addHotword(_ hotword: String) {
        objectWillChange.send()
        queue.async(flags: .barrier) {
            self.hotwords.insert(hotword)
        }
    }

    /// 添加黑名单
    func addToBlacklist(_ word: String) {
        objectWillChange.send()
        queue.async(flags: .barrier) {
            self.blacklist.insert(word)
        }
    }

    /// 获取所有术语（用于 ASR 热词）
    func getAllHotwords() -> [String] {
        queue.sync {
            return Array(terms.union(hotwords))
        }
    }

    /// 检查术语是否在黑名单中
    func isBlacklisted(_ word: String) -> Bool {
        queue.sync {
            return blacklist.contains(word)
        }
    }

    /// 重置所有术语
    func reset() {
        objectWillChange.send()
        queue.async(flags: .barrier) {
            self.terms.removeAll()
            self.hotwords.removeAll()
            self.blacklist.removeAll()
            self.loadDefaultTerms()
        }
    }

    // MARK: - Private

    private func loadDefaultTerms() {
        // 加载默认术语（产品名、技术术语等）
        let defaultTerms = ["MouthType", "Whisper", "Paraformer", "Bailian", "百炼"]
        terms.formUnion(defaultTerms)
    }
}
