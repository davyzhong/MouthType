import XCTest
@testable import MouthType

// MARK: - LogRedaction Tests (Refactored)

final class LogRedactionTests: XCTestCase {

    // MARK: - redactTranscript Tests

    func testRedactTranscriptSensitivePatterns() throws {
        let testCases: [(String, String)] = [
            ("api_key = abcdefghij1234567890", "[REDACTED]"),
            ("test@example.com", "[EMAIL"),
            ("+1-555-123-4567", "[PHONE"),
            ("1234-5678-9012-3456", "[CARD"),
        ]

        for (input, expectedMarker) in testCases {
            let redacted = LogRedaction.redactTranscript(input)
            XCTAssertTrue(
                redacted.contains(expectedMarker),
                "输入 '\(input)' 应包含 '\(expectedMarker)'，但得到：\(redacted)"
            )
        }
    }

    func testRedactTranscriptNoSensitiveData() {
        let text = "Hello world, this is a normal message"
        let redacted = LogRedaction.redactTranscript(text)
        XCTAssertEqual(redacted, text)
    }

    func testRedactTranscriptEdgeCases() {
        XCTAssertEqual(LogRedaction.redactTranscript(""), "")
    }

    // MARK: - redactClipboardContent Tests

    func testRedactClipboardContentSensitive() {
        let sensitiveCases = [
            "password: secret123456",
            "P@ssw0rd!",
        ]

        for content in sensitiveCases {
            let redacted = LogRedaction.redactClipboardContent(content)
            XCTAssertEqual(
                redacted, "[REDACTED]",
                "内容 '\(content)' 应被完全脱敏，但得到：\(redacted)"
            )
        }

        // API key pattern - partial redaction
        let apiKeyContent = "apikey=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let redacted = LogRedaction.redactClipboardContent(apiKeyContent)
        XCTAssertTrue(
            redacted.contains("[REDACTED]"),
            "API Key 内容应包含脱敏标记，但得到：\(redacted)"
        )
    }

    func testRedactClipboardContentNormalText() {
        let content = "Hello, this is normal text"
        let redacted = LogRedaction.redactClipboardContent(content)
        XCTAssertNotEqual(redacted, "[REDACTED]")
        XCTAssertTrue(redacted.contains("Hello") || redacted.contains("normal"))
    }

    // MARK: - redactURL Tests

    func testRedactURLRemovesQueryAndFragment() {
        let testCases: [(String, String)] = [
            ("https://api.example.com/search?q=test&key=secret123", "https://api.example.com/search"),
            ("https://example.com/page#section1", "https://example.com/page"),
            ("https://api.example.com/path?param1=value1&param2=value2&token=abc123", "https://api.example.com/path"),
            ("https://example.com/simple", "https://example.com/simple"),  // 无查询字符串
            ("not-a-valid-url", "not-a-valid-url"),  // 无效 URL
        ]

        for (input, expected) in testCases {
            let redacted = LogRedaction.redactURL(input)
            XCTAssertEqual(redacted, expected, "URL '\(input)' 应脱敏为 '\(expected)'，但得到：\(redacted)")
        }
    }

    // MARK: - redactFilePath Tests

    func testRedactFilePath() {
        let testCases: [(String, String)] = [
            ("/Users/john/Documents/secret/passwords.txt", "[PATH]/passwords.txt"),
            ("file.txt", "[PATH]/file.txt"),
            ("/var/log/system.log", "[PATH]/system.log"),
        ]

        for (input, expected) in testCases {
            let redacted = LogRedaction.redactFilePath(input)
            XCTAssertEqual(redacted, expected, "路径 '\(input)' 应脱敏为 '\(expected)'，但得到：\(redacted)")
        }
    }

    // MARK: - isSensitiveContent Tests

    func testIsSensitiveContentKeywords() {
        let sensitiveKeywords = ["password", "token", "credential", "secret"]

        for keyword in sensitiveKeywords {
            let text = "My \(keyword) is value"
            XCTAssertTrue(
                LogRedaction.isSensitiveContent(text),
                "包含 '\(keyword)' 的文本应被标记为敏感"
            )
        }
    }

    func testIsSensitiveContentNormalText() {
        XCTAssertFalse(LogRedaction.isSensitiveContent("Hello world"))
        XCTAssertFalse(LogRedaction.isSensitiveContent("This is a very long text without any special characters"))
        XCTAssertFalse(LogRedaction.isSensitiveContent(""))
    }

    func testIsSensitiveContentShortTextWithSpecialChars() {
        XCTAssertTrue(LogRedaction.isSensitiveContent("P@ss!"))
    }

    func testIsSensitiveContentCaseInsensitive() {
        XCTAssertTrue(LogRedaction.isSensitiveContent("My PASSWORD is secret"))
        XCTAssertTrue(LogRedaction.isSensitiveContent("The SECRET is hidden"))
    }

    // MARK: - redactLogMessage Tests

    func testRedactLogMessageSecrets() {
        let secretPatterns = [
            "api_key=abcdef1234567890",
            "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            "authorization: abc123def456",
            "Secret=verysecretvalue12345678",
        ]

        for pattern in secretPatterns {
            let redacted = LogRedaction.redactLogMessage(pattern)
            XCTAssertTrue(
                redacted.contains("[REDACTED]"),
                "日志 '\(pattern)' 应包含脱敏标记，但得到：\(redacted)"
            )
        }
    }

    func testRedactLogMessageNoSensitiveData() {
        let message = "Processing user request"
        XCTAssertEqual(LogRedaction.redactLogMessage(message), message)
    }

    // MARK: - SensitiveAppPolicy Tests

    func testSensitiveAppPolicyPasswordManagers() {
        let apps = ["1Password", "Keychain Access", "LastPass", "Bitwarden"]
        for app in apps {
            XCTAssertEqual(
                SensitiveAppPolicy.policy(for: app), .fullyBlocked,
                "应用 '\(app)' 应被完全封锁"
            )
        }
    }

    func testSensitiveAppPolicyFinanceApps() {
        let apps = ["Bank of America", "Alipay", "PayPal", "Stripe"]
        for app in apps {
            XCTAssertEqual(
                SensitiveAppPolicy.policy(for: app), .highPrivacy,
                "应用 '\(app)' 应使用高隐私策略"
            )
        }
    }

    func testSensitiveAppPolicySecurityApps() {
        let apps = ["Security Center", "VPN Client", "Encryption Tool"]
        for app in apps {
            XCTAssertEqual(
                SensitiveAppPolicy.policy(for: app), .localOnly,
                "应用 '\(app)' 应仅允许本地处理"
            )
        }
    }

    func testSensitiveAppPolicyCodeApps() {
        let apps = ["Terminal", "VSCode", "Xcode", "Cursor"]
        for app in apps {
            XCTAssertEqual(
                SensitiveAppPolicy.policy(for: app), .blockAutoLearn,
                "应用 '\(app)' 应封锁自学习"
            )
        }
    }

    func testSensitiveAppPolicyDefault() {
        let apps = ["Safari", "Notes", "Unknown App"]
        for app in apps {
            XCTAssertEqual(
                SensitiveAppPolicy.policy(for: app), .allowFullPipeline,
                "应用 '\(app)' 应允许完整流程"
            )
        }
    }

    func testSensitiveAppPolicyCaseInsensitive() {
        XCTAssertEqual(SensitiveAppPolicy.policy(for: "1password"), .fullyBlocked)
        XCTAssertEqual(SensitiveAppPolicy.policy(for: "ALIPAY"), .highPrivacy)
        XCTAssertEqual(SensitiveAppPolicy.policy(for: "terminal"), .blockAutoLearn)
    }

    // MARK: - AppPolicy.isAllowed Tests

    func testIsAllowedByPolicyLevel() {
        // fullyBlocked: 全部禁止
        XCTAssertFalse(SensitiveAppPolicy.isAllowed(.fullyBlocked, action: .blockAutoLearn))
        XCTAssertFalse(SensitiveAppPolicy.isAllowed(.fullyBlocked, action: .blockCloudReasoning))
        XCTAssertFalse(SensitiveAppPolicy.isAllowed(.fullyBlocked, action: .blockPasteMonitoring))

        // highPrivacy: 全部禁止
        XCTAssertFalse(SensitiveAppPolicy.isAllowed(.highPrivacy, action: .blockAutoLearn))
        XCTAssertFalse(SensitiveAppPolicy.isAllowed(.highPrivacy, action: .blockCloudReasoning))
        XCTAssertFalse(SensitiveAppPolicy.isAllowed(.highPrivacy, action: .blockPasteMonitoring))

        // blockAutoLearn: 仅禁止自学习
        XCTAssertFalse(SensitiveAppPolicy.isAllowed(.blockAutoLearn, action: .blockAutoLearn))
        XCTAssertTrue(SensitiveAppPolicy.isAllowed(.blockAutoLearn, action: .blockCloudReasoning))
        XCTAssertTrue(SensitiveAppPolicy.isAllowed(.blockAutoLearn, action: .blockPasteMonitoring))

        // allowFullPipeline: 全部允许
        XCTAssertTrue(SensitiveAppPolicy.isAllowed(.allowFullPipeline, action: .blockAutoLearn))
        XCTAssertTrue(SensitiveAppPolicy.isAllowed(.allowFullPipeline, action: .blockCloudReasoning))
        XCTAssertTrue(SensitiveAppPolicy.isAllowed(.allowFullPipeline, action: .blockPasteMonitoring))
    }

    // MARK: - Helper Methods Tests

    func testIsCloudReasoningAllowed() {
        XCTAssertTrue(SensitiveAppPolicy.isCloudReasoningAllowed(for: "Safari"))
        XCTAssertFalse(SensitiveAppPolicy.isCloudReasoningAllowed(for: "1Password"))
        XCTAssertFalse(SensitiveAppPolicy.isCloudReasoningAllowed(for: "Bank App"))
        XCTAssertFalse(SensitiveAppPolicy.isCloudReasoningAllowed(for: "VPN"))
    }

    func testIsAutoLearnAllowed() {
        XCTAssertTrue(SensitiveAppPolicy.isAutoLearnAllowed(for: "Safari"))
        XCTAssertFalse(SensitiveAppPolicy.isAutoLearnAllowed(for: "1Password"))
        XCTAssertFalse(SensitiveAppPolicy.isAutoLearnAllowed(for: "Bank App"))
        XCTAssertFalse(SensitiveAppPolicy.isAutoLearnAllowed(for: "Terminal"))
    }

    func testIsPasteMonitoringAllowed() {
        XCTAssertTrue(SensitiveAppPolicy.isPasteMonitoringAllowed(for: "Safari"))
        XCTAssertFalse(SensitiveAppPolicy.isPasteMonitoringAllowed(for: "1Password"))
        XCTAssertFalse(SensitiveAppPolicy.isPasteMonitoringAllowed(for: "Bank App"))
        XCTAssertTrue(SensitiveAppPolicy.isPasteMonitoringAllowed(for: "Terminal"))
    }

    func testHotwordAutoLearnAllowedForSafeApps() {
        XCTAssertTrue(SensitiveAppPolicy.isHotwordCollectionAllowed(for: "Safari", usage: .autoLearn))
    }

    func testHotwordAutoLearnBlockedForCodeApps() {
        XCTAssertFalse(SensitiveAppPolicy.isHotwordCollectionAllowed(for: "Xcode", usage: .autoLearn))
        XCTAssertFalse(SensitiveAppPolicy.isHotwordCollectionAllowed(for: "Terminal", usage: .autoLearn))
    }

    func testHotwordCloudFallbackBlockedForSensitiveApps() {
        XCTAssertFalse(SensitiveAppPolicy.isHotwordCollectionAllowed(for: "1Password", usage: .cloudFallback))
        XCTAssertFalse(SensitiveAppPolicy.isHotwordCollectionAllowed(for: "Bank App", usage: .cloudFallback))
        XCTAssertFalse(SensitiveAppPolicy.isHotwordCollectionAllowed(for: "VPN", usage: .cloudFallback))
    }
}
