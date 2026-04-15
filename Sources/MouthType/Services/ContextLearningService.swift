import AppKit
import ApplicationServices
import Foundation
import os

private let contextLog = RedactedLogger(subsystem: "com.mouthtype", category: "ContextLearning")

enum HotwordUsage {
    case autoLearn
    case cloudFallback
}

/// 上下文学习服务 - 读取前台应用文本框内容，提取术语
/// 使用串行队列确保线程安全
final class ContextLearningService: @unchecked Sendable {
    static let shared = ContextLearningService()

    private let settings = AppSettings.shared
    private var cachedHotwords: [String] = []
    private var lastFetchTime: Date = .distantPast
    private let cacheDuration: TimeInterval = 5.0
    /// 串行队列保护共享状态
    private let queue = DispatchQueue(label: "com.mouthtype.ContextLearningService", qos: .userInteractive)

    private init() {}

    /// 获取当前上下文术语（有缓存）
    /// 使用 barrier sync 以避免死锁 - 允许在队列内重新入队
    func getHotwords(for usage: HotwordUsage = .autoLearn) -> [String] {
        queue.sync(flags: .barrier) {
            _getHotwords(for: usage)
        }
    }

    private func _getHotwords(for usage: HotwordUsage) -> [String] {
        guard settings.contextLearningEnabled else { return [] }

        guard let frontmostAppName = foregroundAppName(),
              SensitiveAppPolicy.isHotwordCollectionAllowed(for: frontmostAppName, usage: usage) else {
            return []
        }

        if Date().timeIntervalSince(lastFetchTime) < cacheDuration {
            return cachedHotwords
        }

        cachedHotwords = fetchHotwords(for: usage)
        lastFetchTime = Date()
        return cachedHotwords
    }

    /// 强制刷新术语
    func refreshHotwords(for usage: HotwordUsage = .autoLearn) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cachedHotwords = self.fetchHotwords(for: usage)
            self.lastFetchTime = Date()
            contextLog.info("Refreshed hotwords: \(self.cachedHotwords.count) terms")
        }
    }

    /// 清理缓存
    func clearCache() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cachedHotwords = []
            self.lastFetchTime = .distantPast
        }
    }

    // MARK: - Private

    private func fetchHotwords(for usage: HotwordUsage) -> [String] {
        guard settings.contextLearningEnabled else { return [] }
        guard let appName = foregroundAppName(),
              SensitiveAppPolicy.isHotwordCollectionAllowed(for: appName, usage: usage) else {
            return []
        }

        // 尝试从当前选中的文本框获取内容
        guard let contextText = getForegroundContextText() else {
            return []
        }

        // 提取术语
        return extractTerms(from: contextText)
    }

    private func foregroundAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// 获取前台应用文本框内容（仅选中文本）
    private func getForegroundContextText() -> String? {
        // 使用 AXUI 获取当前焦点元素
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement as! AXUIElement? else {
            return nil
        }

        // 仅获取选中的文本，不读取完整输入框内容
        var selectedText: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
           let text = selectedText as? String, !text.isEmpty {
            return text
        }

        // 无选中文本时返回 nil，不读取 value 或 placeholder
        return nil
    }

    /// 从文本中提取术语
    private func extractTerms(from text: String) -> [String] {
        // 简单的术语提取策略：
        // 1. 提取名词短语（大写字母开头的词）
        // 2. 提取专业术语（包含连字符、斜杠的词）
        // 3. 提取长度适中的词（3-20 字符）

        var terms: Set<String> = []

        // 分词
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && $0.count <= 30 }

        for word in words {
            let lowercased = word.lowercased()

            // 跳过常见词
            if commonWords.contains(lowercased) {
                continue
            }

            // 添加首字母大写的词（可能是专有名词）
            if word.first?.isUppercase == true {
                terms.insert(word)
            }

            // 添加包含大写字母的词（可能是缩写）
            if word.contains(where: { $0.isUppercase }) {
                terms.insert(word)
            }

            // 添加包含数字和字母的词（可能是产品名）
            if word.contains(where: { $0.isNumber }) && word.contains(where: { $0.isLetter }) {
                terms.insert(word)
            }
        }

        // 提取 CamelCase 术语
        let camelCaseRegex = try? NSRegularExpression(pattern: "[a-z][A-Z][a-zA-Z]+", options: [])
        if let regex = camelCaseRegex {
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range(at: 0),
                   let swiftRange = Range(matchRange, in: text) {
                    terms.insert(String(text[swiftRange]))
                }
            }
        }

        // 提取 术语 - 格式
        let zhEnRegex = try? NSRegularExpression(pattern: "[\\u4e00-\\u9fa5]+-[a-zA-Z]+", options: [])
        if let regex = zhEnRegex {
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range(at: 0),
                   let swiftRange = Range(matchRange, in: text) {
                    terms.insert(String(text[swiftRange]))
                }
            }
        }

        // 限制返回数量
        return Array(terms.prefix(50))
    }

    // 常见中文和英文停用词
    private let commonWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all",
        "can", "had", "her", "was", "one", "our", "out", "day",
        "get", "has", "him", "his", "how", "its", "may", "new",
        "now", "old", "see", "two", "way", "who", "boy", "did",
        "let", "put", "say", "she", "too", "use", "dad", "mom",
        "the", "be", "to", "of", "and", "a", "in", "that", "have",
        "it", "for", "not", "on", "with", "he", "as", "you", "do",
        "at", "this", "but", "his", "by", "from", "they", "we",
        "say", "her", "she", "or", "an", "will", "my", "one",
        "all", "would", "there", "their", "what", "so", "up",
        "出的", "我们", "你们", "他们", "她们", "这个", "那个",
        "什么", "怎么", "如何", "为什么", "因为", "所以", "但是",
        "而且", "或者", "如果", "是否", "可以", "应该", "已经",
        "一个", "一些", "所有", "每个", "任何", "其他", "另外",
    ]
}
