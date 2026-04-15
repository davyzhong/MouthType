import CoreGraphics
import Foundation
import Security
import os

protocol KeychainStore: Sendable {
    func string(forKey key: String, service: String) -> String?
    func setString(_ value: String, forKey key: String, service: String) -> Bool
    func deleteValue(forKey key: String, service: String)
}

struct SystemKeychainStore: KeychainStore {
    func string(forKey key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func setString(_ value: String, forKey key: String, service: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
        }

        return status == errSecSuccess
    }

    func deleteValue(forKey key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum ActivationHotkey: String, CaseIterable, Identifiable {
    case rightOption
    case leftOption
    case rightCommand
    case leftCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption: "右侧 ⌥"
        case .leftOption: "左侧 ⌥"
        case .rightCommand: "右侧 ⌘"
        case .leftCommand: "左侧 ⌘"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .rightOption: 61
        case .leftOption: 58
        case .rightCommand: 54
        case .leftCommand: 55
        }
    }

    var modifierFlag: CGEventFlags {
        switch self {
        case .rightOption, .leftOption:
            .maskAlternate
        case .rightCommand, .leftCommand:
            .maskCommand
        }
    }

    static let defaultValue: ActivationHotkey = .rightOption
}

/// 应用设置 - 单例模式
/// 注意：使用 @unchecked Sendable 是因为：
/// - 所有可变状态 (UserDefaults, Keychain) 是线程安全的
/// - 单例实例在应用生命周期内不会被修改
/// - 所有属性都是 let 或 thread-safe 的 UserDefaults/Keychain 操作
final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()
    static let secretStorageDidFailNotification = Notification.Name("AppSettings.secretStorageDidFail")
    static let secretStorageFailedKeyUserInfoKey = "key"

    private let defaults: UserDefaults
    private let bailianAllowedHost = "dashscope.aliyuncs.com"
    private let bailianRealtimePath = "/api/v1/services/asr/paraformer/realtime"
    private let defaultAIEndpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    private let defaultBailianEndpoint = "wss://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime"
    /// AI endpoint 域名白名单
    private let allowedAIHosts = [
        "dashscope.aliyuncs.com",      // 阿里云百炼
        "api.openai.com",               // OpenAI
        "api.anthropic.com",            // Anthropic
        "generativelanguage.googleapis.com", // Google Gemini
    ]

    /// SSRF 防护：禁止访问的内网 IP 和特殊地址
    private static let blockedIPPatterns: [NSRegularExpression] = {
        let patterns = [
            "^127\\\\.",                  // 127.0.0.0/8 localhost
            "^10\\\\.",                   // 10.0.0.0/8 私有网络
            "^172\\\\.(1[6-9]|2[0-9]|3[0-1])\\\\.",  // 172.16.0.0/12 私有网络
            "^192\\\\.168\\\\.",          // 192.168.0.0/16 私有网络
            "^169\\\\.254\\\\.",          // 169.254.0.0/16 链路本地 (AWS 元数据等)
            "^0\\\\.",                    // 0.0.0.0/8
            "^::1$",                      // IPv6 localhost
            "^fe80:",                     // IPv6 链路本地
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// 检查 IP 地址是否被阻止（SSRF 防护）
    private static func isBlockedIP(_ ip: String) -> Bool {
        for pattern in blockedIPPatterns {
            if pattern.firstMatch(in: ip, range: NSRange(ip.startIndex..., in: ip)) != nil {
                return true
            }
        }
        return false
    }

    /// 检查主机名是否指向内网地址（SSRF 防护）
    private func isInternalHost(_ host: String) -> Bool {
        // 直接是 IP 地址的情况
        if Self.isBlockedIP(host) {
            return true
        }
        // 禁止 localhost 变体
        let normalizedHost = host.lowercased()
        if normalizedHost == "localhost" || normalizedHost.hasSuffix(".localhost") {
            return true
        }
        // 禁止 .local 域名（mDNS）
        if normalizedHost.hasSuffix(".local") {
            return true
        }
        // 禁止 .internal、.intranet 等内网域名
        let internalSuffixes = [".internal", ".intranet", ".corp", ".localdomain"]
        return internalSuffixes.contains { normalizedHost.hasSuffix($0) }
    }
    private let keychainService: String
    private let keychainStore: any KeychainStore

    /// Whisper 二进制文件预期 SHA256 哈希（仅用于 Bundled 二进制）
    /// Homebrew 安装的版本哈希不同，不应验证
    let expectedWhisperBinaryHash: String? = nil // 设置为 nil 禁用验证，或填入实际哈希值

    private let logger = Logger(subsystem: "com.mouthtype", category: "AppSettings")

    init(
        defaults: UserDefaults = .standard,
        keychainService: String = "com.mouthtype.app.settings",
        keychainStore: any KeychainStore = SystemKeychainStore()
    ) {
        self.defaults = defaults
        self.keychainService = keychainService
        self.keychainStore = keychainStore
    }

    // MARK: - ASR
    var asrProvider: ASRProviderType {
        get { ASRProviderType(rawValue: defaults.string(forKey: "asrProvider") ?? "") ?? .localWhisper }
        set { defaults.set(newValue.rawValue, forKey: "asrProvider") }
    }

    var whisperModel: String {
        get {
            let stored = defaults.string(forKey: "whisperModel")
            // 如果用户有 base 设置但 small 模型可用，迁移到 small
            if stored == "base" {
                let smallURL = modelsDirectory.appendingPathComponent("whisper/ggml-small.bin")
                if FileManager.default.fileExists(atPath: smallURL.path) {
                    defaults.set("small", forKey: "whisperModel")
                    return "small"
                }
            }
            if stored == "large" {
                defaults.set("large-v3", forKey: "whisperModel")
                return "large-v3"
            }
            return stored ?? "small"
        }
        set { defaults.set(newValue, forKey: "whisperModel") }
    }

    var preferredLanguage: String {
        get { defaults.string(forKey: "preferredLanguage") ?? "auto" }
        set { defaults.set(newValue, forKey: "preferredLanguage") }
    }

    // MARK: - Interaction
    var activationHotkey: ActivationHotkey {
        get {
            ActivationHotkey(rawValue: defaults.string(forKey: "activationHotkey") ?? "") ?? .defaultValue
        }
        set { defaults.set(newValue.rawValue, forKey: "activationHotkey") }
    }

    var holdThreshold: TimeInterval {
        get { defaults.double(forKey: "holdThreshold") == 0 ? 0.3 : defaults.double(forKey: "holdThreshold") }
        set { defaults.set(newValue, forKey: "holdThreshold") }
    }

    var audioCuesEnabled: Bool {
        get { defaults.object(forKey: "audioCuesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "audioCuesEnabled") }
    }

    // MARK: - AI

    var aiApiKey: String {
        get { secureString(forKey: "aiApiKey") ?? "" }
        set { setSecureString(newValue, forKey: "aiApiKey") }
    }

    var aiEnabled: Bool {
        get { defaults.bool(forKey: "aiEnabled") }
        set { defaults.set(newValue, forKey: "aiEnabled") }
    }

    var aiModelName: String {
        get { defaults.string(forKey: "aiModelName") ?? "qwen-plus" }
        set { defaults.set(newValue, forKey: "aiModelName") }
    }

    var aiEndpoint: String {
        get { defaults.string(forKey: "aiEndpoint") ?? defaultAIEndpoint }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "aiEndpoint") }
    }

    var validatedAIEndpoint: URL? {
        let input = aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        // 步骤 1: 解析 URL 组件
        guard var components = URLComponents(string: input) else {
            logger.warning("URL 解析失败：\(input)")
            return nil
        }

        // 步骤 2: 验证 scheme
        guard let scheme = components.scheme?.lowercased(), scheme == "https" else {
            logger.warning("URL scheme 无效 (必须为 https): \(input)")
            return nil
        }

        // 步骤 3: 验证 host
        guard var host = components.host?.lowercased(), !host.isEmpty else {
            logger.warning("URL host 为空：\(input)")
            return nil
        }

        // 步骤 4: 域名白名单验证
        guard allowedAIHosts.contains(host) else {
            logger.warning("URL host 不在白名单中：\(host)")
            return nil
        }

        // 步骤 5: SSRF 防护 - 检查是否为内网地址
        guard !isInternalHost(host) else {
            logger.warning("SSRF 防护：阻止内网 host: \(host)")
            return nil
        }

        // 步骤 6: 验证 URL 不包含用户信息、查询参数、片段
        guard components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.port == nil || components.port == 443 else {
            logger.warning("URL 包含不允许的组件 (user/password/query/fragment/port): \(input)")
            return nil
        }

        // 步骤 7: 二次验证 - 检查显式 IP 地址
        if Self.isBlockedIP(host) {
            logger.warning("SSRF 防护：阻止访问内网 IP: \(host)")
            return nil
        }

        // 规范化 URL
        components.scheme = "https"
        components.host = host
        let normalizedPath = "/" + components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = normalizedPath == "/" ? "/compatible-mode/v1" : normalizedPath

        return components.url
    }

    var aiChatCompletionsURL: URL? {
        guard let endpoint = validatedAIEndpoint else {
            return nil
        }

        if endpoint.lastPathComponent == "completions",
           endpoint.deletingLastPathComponent().lastPathComponent == "chat" {
            return endpoint
        }

        return endpoint.appendingPathComponent("chat").appendingPathComponent("completions")
    }

    var agentName: String {
        get { defaults.string(forKey: "agentName") ?? "MouthType" }
        set { defaults.set(newValue, forKey: "agentName") }
    }

    var aiIterations: Int {
        get { defaults.object(forKey: "aiIterations") as? Int ?? 1 }
        set { defaults.set(max(1, min(3, newValue)), forKey: "aiIterations") }
    }

    var aiAutoIterate: Bool {
        get { defaults.object(forKey: "aiAutoIterate") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "aiAutoIterate") }
    }

    // MARK: - AI Provider 选择
    var aiProvider: AIProviderType {
        get { AIProviderType(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .bailian }
        set { defaults.set(newValue.rawValue, forKey: "aiProvider") }
    }

    var aiStrictModeEnabled: Bool {
        get { defaults.object(forKey: "aiStrictModeEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "aiStrictModeEnabled") }
    }

    var aiFallbackChainEnabled: Bool {
        get { defaults.object(forKey: "aiFallbackChainEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "aiFallbackChainEnabled") }
    }

    // MARK: - Terminology
    var contextLearningEnabled: Bool {
        get { defaults.object(forKey: "contextLearningEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "contextLearningEnabled") }
    }

    var cloudFallbackHotwordsEnabled: Bool {
        get { defaults.object(forKey: "cloudFallbackHotwordsEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "cloudFallbackHotwordsEnabled") }
    }

    // MARK: - Microphone
    var preferredMicDeviceId: String? {
        get { defaults.string(forKey: "preferredMicDeviceId") }
        set { defaults.set(newValue, forKey: "preferredMicDeviceId") }
    }

    // MARK: - Models Directory

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MouthType/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - First Run

    var hasCompletedOnboarding: Bool {
        get { defaults.object(forKey: "hasCompletedOnboarding") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var whisperModelURL: URL {
        // 优先使用应用 Bundle 中的内置模型
        let bundleModelURL = Bundle.main.url(
            forResource: "whisper-models/ggml-\(whisperModel)",
            withExtension: "bin"
        )
        if let url = bundleModelURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // 回退到用户目录
        return modelsDirectory.appendingPathComponent("whisper/ggml-\(whisperModel).bin")
    }

    // MARK: - Paraformer

    var paraformerModel: String {
        get {
            let stored = defaults.string(forKey: "paraformerModel")
            if stored == "sherpa-onnx-paraformer-zh-int8" {
                defaults.set("model.int8", forKey: "paraformerModel")
                return "model.int8"
            }
            return stored ?? "model.int8"
        }
        set { defaults.set(newValue, forKey: "paraformerModel") }
    }

    var paraformerModelURL: URL {
        // 优先使用应用 Bundle 中的内置模型
        let bundleModelURL = Bundle.main.url(
            forResource: "paraformer-models/\(paraformerModel)",
            withExtension: "onnx"
        )
        if let url = bundleModelURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // 回退到用户目录
        return modelsDirectory.appendingPathComponent("paraformer/\(paraformerModel).onnx")
    }

    var paraformerTokensURL: URL {
        paraformerModelURL.deletingLastPathComponent().appendingPathComponent("tokens.txt")
    }

    // MARK: - Bailian

    var bailianApiKey: String {
        get { secureString(forKey: "bailianApiKey") ?? "" }
        set { setSecureString(newValue, forKey: "bailianApiKey") }
    }

    var bailianEndpoint: String {
        get { defaults.string(forKey: "bailianEndpoint") ?? defaultBailianEndpoint }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "bailianEndpoint") }
    }

    var bailianWebSocketURL: URL? {
        guard let components = normalizedBailianEndpointComponents() else {
            return nil
        }
        return components.url
    }

    var bailianChatCompletionsURL: URL? {
        guard var components = normalizedBailianEndpointComponents() else {
            return nil
        }

        components.scheme = "https"
        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("compatible-mode/v1/chat/completions") {
            components.query = nil
            components.fragment = nil
            return components.url
        }

        if normalizedPath.hasSuffix("compatible-mode/v1") {
            components.path = "/\(normalizedPath)/chat/completions"
        } else {
            components.path = "/compatible-mode/v1/chat/completions"
        }

        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func secureString(forKey key: String) -> String? {
        if let value = keychainStore.string(forKey: key, service: keychainService) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let legacyValue = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyValue.isEmpty else {
            return nil
        }

        // 原子迁移：先尝试写入 Keychain，成功后再删除 UserDefaults
        let migrated = setKeychainString(legacyValue, forKey: key)
        if migrated {
            defaults.removeObject(forKey: key)  // 成功后删除旧值
            return legacyValue
        }

        // 迁移失败：保留 UserDefaults 值，仅记录警告
        postSecretStorageFailure(forKey: key)
        logger.warning("Keychain 写入失败，保留 legacy 值（未删除）：key=\(key)")
        return legacyValue  // 返回旧值以供继续使用
    }

    private func setSecureString(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            defaults.removeObject(forKey: key)
            deleteKeychainValue(forKey: key)
            return
        }

        defaults.removeObject(forKey: key)
        let success = setKeychainString(trimmed, forKey: key)
        if !success {
            postSecretStorageFailure(forKey: key)
            logger.error("设置安全字符串失败，未持久化到不安全存储：key=\(key)")
        }
    }

    private func postSecretStorageFailure(forKey key: String) {
        NotificationCenter.default.post(
            name: Self.secretStorageDidFailNotification,
            object: self,
            userInfo: [Self.secretStorageFailedKeyUserInfoKey: key]
        )
    }

    private func setKeychainString(_ value: String, forKey key: String) -> Bool {
        guard value.data(using: .utf8) != nil else {
            logger.error("Keychain 写入失败：无法将值转换为 Data，key=\(key)")
            return false
        }

        let success = keychainStore.setString(value, forKey: key, service: keychainService)
        if !success {
            logger.error("Keychain 写入失败：key=\(key)")
        }
        return success
    }

    private func deleteKeychainValue(forKey key: String) {
        keychainStore.deleteValue(forKey: key, service: keychainService)
    }

    private func keychainQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
    }

    private func normalizedBailianEndpointComponents() -> URLComponents? {
        guard var components = URLComponents(string: bailianEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              scheme == "wss",
              host == bailianAllowedHost,
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443 else {
            return nil
        }

        components.scheme = "wss"
        components.host = host
        components.query = nil
        components.fragment = nil

        let normalizedPath = "/" + components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = normalizedPath == "/" ? bailianRealtimePath : normalizedPath

        guard components.path == bailianRealtimePath else {
            return nil
        }

        return components
    }
}
