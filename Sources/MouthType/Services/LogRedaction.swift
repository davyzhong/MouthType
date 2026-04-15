import Foundation
import os

/// 日志脱敏工具
///
/// 确保敏感信息不会泄露到日志中
struct LogRedaction {
    private static let redactMarker = "[REDACTED]"

    /// 脱敏转写文本
    /// - Parameter text: 原始转写文本
    /// - Returns: 脱敏后的文本
    static func redactTranscript(_ text: String) -> String {
        var result = text

        // 脱敏 API 密钥模式
        let apiKeyPattern = #"(?i)(api[_-]?key|apikey|token|secret|password)\s*[=:]\s*['"]?[a-zA-Z0-9]{16,}['"]?"#
        if let regex = try? NSRegularExpression(pattern: apiKeyPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1=\(redactMarker)")
        }

        // 脱敏邮箱地址
        let emailPattern = #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"#
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[EMAIL\(redactMarker)]")
        }

        // 脱敏电话号码
        let phonePattern = #"\b(?:\+?(\d{1,3}))?[-. (]*(\d{3})[-. )]*(\d{3})[-. ]*(\d{4})\b"#
        if let regex = try? NSRegularExpression(pattern: phonePattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[PHONE\(redactMarker)]")
        }

        // 脱敏信用卡号
        let cardPattern = #"\b(?:\d{4}[- ]?){3}\d{4}\b"#
        if let regex = try? NSRegularExpression(pattern: cardPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[CARD\(redactMarker)]")
        }

        return result
    }

    /// 脱敏剪贴板内容
    /// - Parameter content: 剪贴板内容
    /// - Returns: 脱敏后的内容
    static func redactClipboardContent(_ content: String) -> String {
        // 检测是否为敏感内容
        if isSensitiveContent(content) {
            return redactMarker
        }
        return redactTranscript(content)
    }

    /// 脱敏 URL（移除查询参数）
    /// - Parameter url: 原始 URL
    /// - Returns: 脱敏后的 URL
    static func redactURL(_ url: String) -> String {
        guard var components = URLComponents(string: url) else {
            return url
        }
        // 移除查询参数
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url
    }

    /// 脱敏文件路径（保留文件名，隐藏路径）
    /// - Parameter path: 文件路径
    /// - Returns: 脱敏后的路径
    static func redactFilePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        return "[PATH]/\(fileName)"
    }

    /// 检查内容是否敏感
    /// - Parameter content: 内容
    /// - Returns: 是否敏感
    static func isSensitiveContent(_ content: String) -> Bool {
        // 检查是否包含密码相关关键词
        let sensitiveKeywords = ["password", "passwd", "pwd", "secret", "token", "credential"]
        let lowercased = content.lowercased()

        for keyword in sensitiveKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }

        // 检查是否为短文本且包含特殊字符（可能是密码）
        if content.count < 50 && content.contains(where: { "!@#$%^&*()".contains($0) }) {
            return true
        }

        return false
    }

    /// 脱敏日志消息
    /// - Parameter message: 日志消息
    /// - Returns: 脱敏后的消息
    static func redactLogMessage(_ message: String) -> String {
        var result = message

        // 脱敏常见的密钥模式
        let patterns = [
            #"(?i)api[_-]?key\s*[=:]\s*['"]?[a-zA-Z0-9]{16,}['"]?"#,
            #"(?i)bearer\s+[a-zA-Z0-9._-]+"#,
            #"(?i)authorization\s*:\s*[a-zA-Z0-9._-]+"#,
            #"(?i)secret\s*[=:]\s*['"]?[a-zA-Z0-9]{8,}['"]?"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: redactMarker)
            }
        }

        return result
    }
}

/// 敏感应用策略
///
/// 定义在特定应用中的隐私和行为边界
struct SensitiveAppPolicy {
    let appBundleId: String
    let appName: String
    let policy: AppPolicy

    struct AppPolicy: OptionSet, Sendable {
        let rawValue: Int

        /// 允许完整处理流程
        static let allowFullPipeline = AppPolicy(rawValue: 1 << 0)

        /// 阻止自动学习
        static let blockAutoLearn = AppPolicy(rawValue: 1 << 1)

        /// 阻止云端推理
        static let blockCloudReasoning = AppPolicy(rawValue: 1 << 2)

        /// 阻止粘贴监控
        static let blockPasteMonitoring = AppPolicy(rawValue: 1 << 3)

        /// 阻止注入
        static let blockInjection = AppPolicy(rawValue: 1 << 4)

        /// 仅本地处理
        static let localOnly: AppPolicy = [.blockCloudReasoning]

        /// 高隐私模式
        static let highPrivacy: AppPolicy = [.blockAutoLearn, .blockCloudReasoning, .blockPasteMonitoring]

        /// 完全阻止（敏感应用）
        static let fullyBlocked: AppPolicy = [.blockAutoLearn, .blockCloudReasoning, .blockPasteMonitoring, .blockInjection]
    }

    /// 获取应用的策略
    /// - Parameter appName: 应用名称
    /// - Returns: 应用策略
    static func policy(for appName: String) -> AppPolicy {
        let lowercased = appName.lowercased()

        // 密码管理器 - 完全阻止
        let passwordManagers = ["1password", "keychain", "lastpass", "bitwarden", "keeper"]
        if passwordManagers.contains(where: { lowercased.contains($0) }) {
            return .fullyBlocked
        }

        // 金融应用 - 高隐私
        let financeApps = ["bank", "alipay", "wechat pay", "paypal", "stripe", "finance"]
        if financeApps.contains(where: { lowercased.contains($0) }) {
            return .highPrivacy
        }

        // 安全相关应用 - 阻止云端
        let securityApps = ["security", "encryption", "vpn", "firewall"]
        if securityApps.contains(where: { lowercased.contains($0) }) {
            return .localOnly
        }

        // 终端/IDE - 阻止自动学习（代码可能包含敏感信息）
        let codeApps = ["terminal", "iterm", "xcode", "vscode", "cursor", "jetbrains"]
        if codeApps.contains(where: { lowercased.contains($0) }) {
            return .blockAutoLearn
        }

        // 默认允许
        return .allowFullPipeline
    }

    /// 检查是否允许某项操作
    /// - Parameters:
    ///   - policy: 应用策略
    ///   - action: 要检查的操作
    /// - Returns: 是否允许
    static func isAllowed(_ policy: AppPolicy, action: AppPolicy) -> Bool {
        // 如果完全阻止，则不允许任何操作
        if policy == .fullyBlocked {
            return false
        }

        // 检查是否阻止了特定操作
        if policy.contains(action) {
            return false
        }

        return true
    }

    /// 检查是否允许云端推理
    static func isCloudReasoningAllowed(for appName: String) -> Bool {
        let policy = self.policy(for: appName)
        return !policy.contains(.blockCloudReasoning) && policy != .fullyBlocked
    }

    /// 检查是否允许自动学习
    static func isAutoLearnAllowed(for appName: String) -> Bool {
        let policy = self.policy(for: appName)
        return !policy.contains(.blockAutoLearn) && policy != .fullyBlocked
    }

    /// 检查是否允许粘贴监控
    static func isPasteMonitoringAllowed(for appName: String) -> Bool {
        let policy = self.policy(for: appName)
        return !policy.contains(.blockPasteMonitoring) && policy != .fullyBlocked
    }

    /// 检查是否允许收集 hotwords
    static func isHotwordCollectionAllowed(for appName: String, usage: HotwordUsage) -> Bool {
        switch usage {
        case .autoLearn:
            return isAutoLearnAllowed(for: appName)
        case .cloudFallback:
            return isAutoLearnAllowed(for: appName) && isCloudReasoningAllowed(for: appName)
        }
    }
}

/// 日志脱敏记录器
///
/// 包装 os.Logger，自动脱敏敏感信息
struct RedactedLogger {
    private let logger: Logger

    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func trace(_ message: String) {
        logger.trace("\(LogRedaction.redactLogMessage(message))")
    }

    func debug(_ message: String) {
        logger.debug("\(LogRedaction.redactLogMessage(message))")
    }

    func info(_ message: String) {
        logger.info("\(LogRedaction.redactLogMessage(message))")
    }

    func warning(_ message: String) {
        logger.warning("\(LogRedaction.redactLogMessage(message))")
    }

    func error(_ message: String) {
        logger.error("\(LogRedaction.redactLogMessage(message))")
    }

    func critical(_ message: String) {
        logger.critical("\(LogRedaction.redactLogMessage(message))")
    }
}
