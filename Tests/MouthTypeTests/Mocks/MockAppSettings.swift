import XCTest
@testable import MouthType

/// Mock 应用设置 - 用于测试
///
/// 使用内存中的 UserDefaults，不触及真实配置
final class MockAppSettings: @unchecked Sendable {
    private let defaults: UserDefaults
    private let configStore: ConfigFileStore
    
    var asrProvider: ASRProviderType {
        get {
            if let raw = defaults.string(forKey: "asrProvider"),
               let type = ASRProviderType(rawValue: raw) {
                return type
            }
            return .localWhisper
        }
        set { defaults.set(newValue.rawValue, forKey: "asrProvider") }
    }
    
    var aiEnabled: Bool {
        get { defaults.bool(forKey: "aiEnabled") }
        set { defaults.set(newValue, forKey: "aiEnabled") }
    }
    
    var agentName: String {
        get { defaults.string(forKey: "agentName") ?? "" }
        set { defaults.set(newValue, forKey: "agentName") }
    }
    
    var cloudFallbackHotwordsEnabled: Bool {
        get { defaults.bool(forKey: "cloudFallbackHotwordsEnabled") }
        set { defaults.set(newValue, forKey: "cloudFallbackHotwordsEnabled") }
    }
    
    var activationHotkey: ActivationHotkey {
        get {
            if let raw = defaults.string(forKey: "activationHotkey"),
               let hotkey = ActivationHotkey(rawValue: raw) {
                return hotkey
            }
            return .rightOption
        }
        set { defaults.set(newValue.rawValue, forKey: "activationHotkey") }
    }
    
    init() {
        let suiteName = "MockAppSettings.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!
        self.defaults.removePersistentDomain(forName: suiteName)
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mouthtype_mock_tests", isDirectory: true)
        let configURL = tempDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
        
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        self.configStore = ConfigFileStore(configURL: configURL)
    }
    
    func reset() {
        if let suiteName = defaults.volatileDomainNames.first {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
