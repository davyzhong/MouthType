import Security
import XCTest
@testable import MouthType

// MARK: - AppSettings Tests (Refactored)

final class AppSettingsTests: XCTestCase {
    private var suiteName = ""
    private var keychainService = ""
    private var defaults: UserDefaults!
    private var appSettings: AppSettings!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        keychainService = "com.mouthtype.tests.\(suiteName)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        appSettings = AppSettings(defaults: defaults, keychainService: keychainService)
    }

    override func tearDown() {
        appSettings.aiApiKey = ""
        appSettings.bailianApiKey = ""
        appSettings = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        keychainService = ""
        super.tearDown()
    }

    private func keychainString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    // MARK: - Bailian WebSocket URL Tests

    func testBailianWebSocketURLWithValidEndpoints() {
        let settings = appSettings!
        let validCases = [
            "wss://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime",
            "wss://dashscope.aliyuncs.com:443/api/v1/services/asr/paraformer/realtime",
        ]

        for (i, endpoint) in validCases.enumerated() {
            settings.bailianEndpoint = endpoint
            XCTAssertNotNil(
                settings.bailianWebSocketURL,
                "有效端点 \(i) 应被接受：\(endpoint)"
            )
        }
    }

    func testBailianWebSocketURLWithInvalidEndpoints() {
        let settings = appSettings!
        let invalidCases: [(String, String)] = [
            ("wss://example.com/api/v1/services/asr/paraformer/realtime", "非可信主机"),
            ("wss://dashscope.aliyuncs.com/compatible-mode/v1", "非预期路径"),
            ("wss://dashscope.aliyuncs.com:8443/api/v1/services/asr/paraformer/realtime", "非标准端口"),
            ("ws://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime", "HTTP 方案"),
            ("", "空字符串"),
            ("   ", "纯空白"),
            ("wss://user:pass@dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime", "URL 中的凭证"),
        ]

        for (endpoint, reason) in invalidCases {
            settings.bailianEndpoint = endpoint
            XCTAssertNil(
                settings.bailianWebSocketURL,
                "无效端点应被拒绝 (\(reason)): \(endpoint)"
            )
        }
    }

    func testBailianWebSocketURLStripsQueryString() {
        let settings = appSettings!
        settings.bailianEndpoint = "wss://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime?token=abc"

        XCTAssertNotNil(settings.bailianWebSocketURL)
        XCTAssertFalse(settings.bailianWebSocketURL!.absoluteString.contains("token"))
    }

    func testBailianEndpointTrimsWhitespace() {
        let settings = appSettings!
        settings.bailianEndpoint = "  wss://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime  "

        XCTAssertEqual(
            settings.bailianWebSocketURL?.absoluteString,
            "wss://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime"
        )
    }

    func testBailianChatCompletionsURLDerivesTrustedHTTPSURL() {
        let settings = appSettings!
        settings.bailianEndpoint = "wss://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime"

        XCTAssertEqual(
            settings.bailianChatCompletionsURL?.absoluteString,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        )
    }

    // MARK: - AI Endpoint Allowlist Tests

    func testValidatedAIEndpointAcceptsAllowedHosts() {
        let settings = appSettings!
        let allowedHosts = [
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "https://api.openai.com/v1",
            "https://api.anthropic.com/v1",
            "https://generativelanguage.googleapis.com/v1",
        ]

        for endpoint in allowedHosts {
            settings.aiEndpoint = endpoint
            XCTAssertNotNil(
                settings.validatedAIEndpoint,
                "应接受允许的主机：\(endpoint)"
            )
        }
    }

    func testValidatedAIEndpointRejectsUnallowedHosts() {
        let settings = appSettings!
        let rejectedHosts: [(String, String)] = [
            ("https://evil.attacker.com/webhook", "任意主机"),
            ("https://169.254.169.254/latest/meta-data", "元数据端点"),
            ("https://localhost:8080/api", "本地主机"),
        ]

        for (endpoint, reason) in rejectedHosts {
            settings.aiEndpoint = endpoint
            XCTAssertNil(
                settings.validatedAIEndpoint,
                "应拒绝不可信主机 (\(reason)): \(endpoint)"
            )
        }
    }

    func testValidatedAIEndpointRequiresHTTPS() {
        let settings = appSettings!
        settings.aiEndpoint = "http://dashscope.aliyuncs.com/compatible-mode/v1"
        XCTAssertNil(settings.validatedAIEndpoint, "应拒绝 HTTP 方案")
    }

    // MARK: - API Key Keychain Tests

    func testAIAPIKeyPersistsInKeychain() {
        let settings = appSettings!
        settings.aiApiKey = "sk-keychain-test"

        XCTAssertEqual(settings.aiApiKey, "sk-keychain-test")
        XCTAssertEqual(keychainString(forKey: "aiApiKey"), "sk-keychain-test")
        XCTAssertNil(defaults.string(forKey: "aiApiKey"))
    }

    func testClearingBailianAPIKeyRemovesKeychainValue() {
        let settings = appSettings!
        settings.bailianApiKey = "bailian-secret"
        settings.bailianApiKey = ""

        XCTAssertEqual(settings.bailianApiKey, "")
        XCTAssertNil(keychainString(forKey: "bailianApiKey"))
    }

    func testLegacyAIAPIKeyMigratesFromUserDefaultsToKeychain() {
        let settings = appSettings!
        defaults.set("legacy-ai-key", forKey: "aiApiKey")

        XCTAssertEqual(settings.aiApiKey, "legacy-ai-key")
        XCTAssertEqual(keychainString(forKey: "aiApiKey"), "legacy-ai-key")
        XCTAssertNil(defaults.string(forKey: "aiApiKey"))
    }

    func testCloudFallbackHotwordsDisabledByDefault() {
        let settings = appSettings!
        XCTAssertFalse(settings.cloudFallbackHotwordsEnabled)
    }
}

// MARK: - AppState Error Recovery

final class AppStateTests: XCTestCase {
    func testTransitionToIdleClearsStreamingState() {
        let state = AppState()
        state.streamingText = "some text"
        state.audioLevel = 0.5
        state.errorMessage = "old error"

        state.transition(to: .idle)

        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.audioLevel, 0)
        XCTAssertEqual(state.errorMessage, "")
        XCTAssertEqual(state.dictationState, .idle)
    }

    func testTransitionToErrorSetsErrorMessage() {
        let state = AppState()
        state.transition(to: .error("test error"))

        XCTAssertEqual(state.errorMessage, "test error")
        XCTAssertEqual(state.dictationState, .error("test error"))
    }

    func testErrorToIdleRecovery() {
        let state = AppState()
        state.transition(to: .error("test error"))
        state.transition(to: .idle)

        XCTAssertEqual(state.dictationState, .idle)
        XCTAssertEqual(state.errorMessage, "")
        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.audioLevel, 0)
    }

    func testStreamingToIdleClearsStreamingText() {
        let state = AppState()
        state.transition(to: .streaming("partial result"))
        state.transition(to: .idle)

        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.dictationState, .idle)
    }

    func testIsRecordingReturnsTrueForRecordingAndStreaming() {
        let state = AppState()

        state.transition(to: .recording)
        XCTAssertTrue(state.isRecording)

        state.transition(to: .streaming("text"))
        XCTAssertTrue(state.isRecording)

        state.transition(to: .idle)
        XCTAssertFalse(state.isRecording)

        state.transition(to: .processing)
        XCTAssertFalse(state.isRecording)

        state.transition(to: .error("err"))
        XCTAssertFalse(state.isRecording)
    }

    func testMultipleErrorRecoveryCycles() {
        let state = AppState()

        for i in 0..<5 {
            state.transition(to: .error("error \(i)"))
            XCTAssertEqual(state.dictationState, .error("error \(i)"))
            state.transition(to: .idle)
            XCTAssertEqual(state.dictationState, .idle)
        }

        XCTAssertEqual(state.errorMessage, "")
        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.audioLevel, 0)
    }
}

// MARK: - AI Provider Tests

final class AIProviderTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var keychainService = ""
    private var appSettings: AppSettings!

    override func setUp() {
        super.setUp()
        suiteName = "AIProviderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        keychainService = "com.mouthtype.tests.ai.\(suiteName)"
        appSettings = AppSettings(defaults: defaults, keychainService: keychainService)
    }

    override func tearDown() {
        appSettings.aiApiKey = ""
        appSettings = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        keychainService = ""
        super.tearDown()
    }

    func testBailianAIProviderAvailability() {
        let settings = appSettings!
        let keychain = SystemKeychainStore()

        // 清理
        keychain.deleteValue(forKey: "bailian_api_key", service: "MouthType.APIKeys")

        // 测试用例：有效配置应可用
        settings.aiApiKey = "sk-test-key"
        settings.aiEndpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        keychain.setString("sk-test-key", forKey: "bailian_api_key", service: "MouthType.APIKeys")

        var provider = BailianAIProvider(settings: settings)
        XCTAssertTrue(provider.isAvailable, "有效配置应可用")

        // 测试用例：无 API Key 不可用
        keychain.deleteValue(forKey: "bailian_api_key", service: "MouthType.APIKeys")
        provider = BailianAIProvider(settings: settings)
        XCTAssertFalse(provider.isAvailable, "无 API Key 应不可用")

        // 测试用例：HTTP 端点不可用
        keychain.setString("sk-test-key", forKey: "bailian_api_key", service: "MouthType.APIKeys")
        settings.aiEndpoint = "http://insecure.example.com"
        provider = BailianAIProvider(settings: settings)
        XCTAssertFalse(provider.isAvailable, "HTTP 端点应不可用")
    }

    func testBailianAIProviderRejectsInvalidEndpoints() {
        let settings = appSettings!
        let keychain = SystemKeychainStore()
        keychain.setString("sk-test-key", forKey: "bailian_api_key", service: "MouthType.APIKeys")
        settings.aiApiKey = "sk-test-key"

        let invalidEndpoints: [(String, String)] = [
            ("https://user:pass@example.com/compatible-mode/v1", "URL 中的凭证"),
            ("https://example.com/compatible-mode/v1?token=abc", "查询字符串"),
            ("https://example.com/compatible-mode/v1#fragment", "URL 片段"),
            ("https://example.com:8443/compatible-mode/v1", "非标准端口"),
        ]

        for (endpoint, reason) in invalidEndpoints {
            settings.aiEndpoint = endpoint
            let provider = BailianAIProvider(settings: settings)
            XCTAssertFalse(
                provider.isAvailable,
                "应拒绝无效端点 (\(reason)): \(endpoint)"
            )
        }
    }

    func testBailianAIProviderBuildsChatCompletionsEndpointFromBaseURL() {
        let settings = appSettings!
        settings.aiApiKey = "sk-test-key"
        settings.aiEndpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"

        XCTAssertEqual(
            settings.aiChatCompletionsURL?.absoluteString,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        )
    }
}

// MARK: - WhisperProvider Consistency

final class WhisperProviderTests: XCTestCase {
    func testAvailabilityErrorAndIsAvailableAreConsistent() {
        let provider = WhisperProvider()
        XCTAssertEqual(provider.isAvailable, provider.availabilityError == nil)
    }

    func testAvailabilityErrorIsModelOrBinaryRelated() {
        let provider = WhisperProvider()
        if let error = provider.availabilityError {
            let isModelOrBinaryError: Bool
            if case .modelNotFound = error {
                isModelOrBinaryError = true
            } else if case .binaryNotFound = error {
                isModelOrBinaryError = true
            } else {
                isModelOrBinaryError = false
            }
            XCTAssertTrue(isModelOrBinaryError, "意外错误类型：\(error)")
        }
    }
}
