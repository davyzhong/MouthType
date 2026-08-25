import Foundation
import os

/// 配置文件存储 - 用于存储 API Key 等敏感信息
/// 文件位置：~/.mouthtype/config.json
/// 注意：此文件不应提交到 GitHub
final class ConfigFileStore: @unchecked Sendable {
    static let shared = ConfigFileStore()

    private let configDirectory: URL
    private let configURL: URL
    private let logger = Logger(subsystem: "com.mouthtype", category: "ConfigFileStore")

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// 初始化默认配置文件（生产环境）
    init() {
        // 配置文件存储目录：~/.mouthtype/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = homeDir.appendingPathComponent(".mouthtype", isDirectory: true)
        configURL = configDirectory.appendingPathComponent("config.json")

        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]  // 仅所有者可读写执行
        )
    }

    /// 初始化自定义配置文件（用于测试）
    init(configURL: URL) {
        self.configURL = configURL
        self.configDirectory = configURL.deletingLastPathComponent()

        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// 读取配置
    func readConfig() -> Config? {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            logger.debug("配置文件不存在")
            return nil
        }

        do {
            let data = try Data(contentsOf: configURL)
            let config = try decoder.decode(Config.self, from: data)
            logger.debug("成功读取配置文件")
            return config
        } catch {
            logger.error("读取配置文件失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 保存配置
    func saveConfig(_ config: Config) -> Bool {
        do {
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)

            // 设置文件权限为仅所有者可读写 (0o600)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: configURL.path
            )

            let aiKeyStatus = config.aiApiKey != nil ? "已设置" : "nil"
            let bailianKeyStatus = config.bailianApiKey != nil ? "已设置" : "nil"
            logger.info("成功保存配置文件：ai_api_key=\(aiKeyStatus), bailian_api_key=\(bailianKeyStatus)")
            return true
        } catch {
            logger.error("保存配置文件失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 获取 API Key
    func getAPIKey(for provider: APIKeyProvider) -> String? {
        guard let config = readConfig() else { return nil }

        let value: String?
        switch provider {
        case .ai:
            value = config.aiApiKey
        case .bailian:
            value = config.bailianApiKey
        }

        let providerName: String
        let valueStatus: String
        switch provider {
        case .ai:
            providerName = "ai"
            valueStatus = config.aiApiKey != nil ? "已设置" : "nil"
        case .bailian:
            providerName = "bailian"
            valueStatus = config.bailianApiKey != nil ? "已设置" : "nil"
        }

        logger.info("读取 API Key: \(providerName) = \(valueStatus)")
        return value
    }

    /// 设置 API Key
    func setAPIKey(_ key: String, for provider: APIKeyProvider) -> Bool {
        logger.info("设置 API Key: \(provider == .ai ? "ai" : "bailian") = \(key.isEmpty ? "空" : "已设置")")

        var config = readConfig() ?? Config()
        logger.info("当前配置：ai_api_key=\(config.aiApiKey != nil ? "已设置" : "nil"), bailian_api_key=\(config.bailianApiKey != nil ? "已设置" : "nil")")

        switch provider {
        case .ai:
            config.aiApiKey = key.isEmpty ? nil : key
        case .bailian:
            config.bailianApiKey = key.isEmpty ? nil : key
        }

        logger.info("保存后配置：ai_api_key=\(config.aiApiKey != nil ? "已设置" : "nil"), bailian_api_key=\(config.bailianApiKey != nil ? "已设置" : "nil")")

        let success = saveConfig(config)
        logger.info("保存结果：\(success ? "成功" : "失败")")
        return success
    }

    /// 清除配置（用于测试）
    func clear() {
        try? FileManager.default.removeItem(at: configURL)
    }

    /// 配置文件结构
    struct Config: Codable {
        enum CodingKeys: String, CodingKey {
            case aiApiKey = "ai_api_key"
            case bailianApiKey = "bailian_api_key"
        }

        var aiApiKey: String?
        var bailianApiKey: String?

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            aiApiKey = try container.decodeIfPresent(String.self, forKey: .aiApiKey)
            bailianApiKey = try container.decodeIfPresent(String.self, forKey: .bailianApiKey)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(aiApiKey, forKey: .aiApiKey)
            try container.encodeIfPresent(bailianApiKey, forKey: .bailianApiKey)
        }
    }

    enum APIKeyProvider {
        case ai
        case bailian
    }
}
