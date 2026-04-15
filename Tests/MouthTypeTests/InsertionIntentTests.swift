import XCTest
@testable import MouthType

// MARK: - InsertionIntent Tests (Refactored)

final class InsertionIntentTests: XCTestCase {

    // MARK: - InsertionIntent Tests

    func testInsertionIntentDisplayNamesAndDescriptions() {
        let testCases: [(InsertionIntent, String, String)] = [
            (.insert, "插入", "插入"),
            (.replaceSelection, "替换选中", "替换"),
            (.appendAfterSelection, "追加", "追加"),
            (.smart, "智能", "自动"),
        ]

        for (intent, expectedName, expectedDescKeyword) in testCases {
            XCTAssertEqual(intent.displayName, expectedName)
            XCTAssertTrue(intent.description.contains(expectedDescKeyword))
        }
    }

    // MARK: - InsertionOutcomeMode Tests

    func testInsertionOutcomeModeIsSuccess() {
        XCTAssertTrue(InsertionOutcomeMode.inserted.isSuccess)
        XCTAssertTrue(InsertionOutcomeMode.replaced.isSuccess)
        XCTAssertTrue(InsertionOutcomeMode.appended.isSuccess)
        XCTAssertFalse(InsertionOutcomeMode.copied.isSuccess)
        XCTAssertFalse(InsertionOutcomeMode.failed(reason: "test").isSuccess)
    }

    func testInsertionOutcomeModeDisplayNames() {
        let testCases: [(InsertionOutcomeMode, String)] = [
            (.inserted, "已插入"),
            (.replaced, "已替换"),
            (.appended, "已追加"),
            (.copied, "已复制"),
        ]

        for (mode, expectedName) in testCases {
            XCTAssertEqual(mode.displayName, expectedName)
        }

        // 失败情况
        let failedMode = InsertionOutcomeMode.failed(reason: "test")
        XCTAssertTrue(failedMode.displayName.contains("失败"))
    }

    // MARK: - AppFamily Tests

    func testAppFamilyDetectIDEApps() {
        let apps = ["Xcode", "VSCode", "Cursor", "IntelliJ", "PyCharm", "Zed"]
        for app in apps {
            XCTAssertEqual(AppFamily.detect(appName: app), .ide, "应用 '\(app)' 应被识别为 IDE")
        }
    }

    func testAppFamilyDetectTerminalApps() {
        let apps = ["Terminal", "iTerm", "Warp", "Kitty", "Alacritty"]
        for app in apps {
            XCTAssertEqual(AppFamily.detect(appName: app), .terminal, "应用 '\(app)' 应被识别为终端")
        }
    }

    func testAppFamilyDetectDocumentApps() {
        let apps = ["Pages", "Word", "Notion", "Bear", "Obsidian"]
        for app in apps {
            XCTAssertEqual(AppFamily.detect(appName: app), .document, "应用 '\(app)' 应被识别为文档应用")
        }
    }

    func testAppFamilyDetectBrowserApps() {
        let apps = ["Safari", "Chrome", "Firefox", "Arc", "Edge"]
        for app in apps {
            XCTAssertEqual(AppFamily.detect(appName: app), .browser, "应用 '\(app)' 应被识别为浏览器")
        }
    }

    func testAppFamilyDetectChatApps() {
        let apps = ["WeChat", "Messages", "Slack", "Discord", "Telegram"]
        for app in apps {
            XCTAssertEqual(AppFamily.detect(appName: app), .chat, "应用 '\(app)' 应被识别为聊天应用")
        }
    }

    func testAppFamilyDetectUnknownApps() {
        let apps = ["Unknown App", "Preview", "Finder"]
        for app in apps {
            XCTAssertEqual(AppFamily.detect(appName: app), .native, "应用 '\(app)' 应被识别为原生应用")
        }
    }

    func testAppFamilyCaseInsensitive() {
        let testCases: [(String, AppFamily)] = [
            ("xcode", .ide),
            ("SAFARI", .browser),
            ("WeChat", .chat),
            ("terminal", .terminal),
        ]

        for (appName, expectedFamily) in testCases {
            XCTAssertEqual(AppFamily.detect(appName: appName), expectedFamily, "应用 '\(appName)' 应被识别为 \(expectedFamily)")
        }
    }

    // MARK: - InsertionCompatibilityProfile Tests

    func testProfileForBrowser() {
        let profile = InsertionCompatibilityProfile.profile(for: .browser)

        XCTAssertEqual(profile.appFamily, .browser)
        XCTAssertEqual(profile.defaultIntent, .insert)
        XCTAssertTrue(profile.enableSelectionDetection)
        XCTAssertFalse(profile.enableSmartAppend)
        XCTAssertEqual(profile.retryCount, 3)
        XCTAssertTrue(profile.enableFallbackCopy)
        XCTAssertTrue(profile.requiresSpecialHandling)
    }

    func testProfileForTerminal() {
        let profile = InsertionCompatibilityProfile.profile(for: .terminal)

        XCTAssertEqual(profile.appFamily, .terminal)
        XCTAssertEqual(profile.defaultIntent, .appendAfterSelection)
        XCTAssertFalse(profile.enableSelectionDetection)
        XCTAssertEqual(profile.retryCount, 2)
        XCTAssertTrue(profile.requiresSpecialHandling)
        XCTAssertTrue(profile.specialHandlingNotes.contains("Cmd+Shift+V"))
    }

    func testProfileForIDE() {
        let profile = InsertionCompatibilityProfile.profile(for: .ide)

        XCTAssertEqual(profile.appFamily, .ide)
        XCTAssertEqual(profile.defaultIntent, .replaceSelection)
        XCTAssertTrue(profile.enableSelectionDetection)
        XCTAssertEqual(profile.retryCount, 2)
        XCTAssertTrue(profile.enableFallbackCopy)
    }

    func testProfileForDocumentAndChat() {
        // 文档
        let docProfile = InsertionCompatibilityProfile.profile(for: .document)
        XCTAssertEqual(docProfile.appFamily, .document)
        XCTAssertEqual(docProfile.defaultIntent, .insert)
        XCTAssertTrue(docProfile.enableSelectionDetection)
        XCTAssertTrue(docProfile.enableSmartAppend)

        // 聊天
        let chatProfile = InsertionCompatibilityProfile.profile(for: .chat)
        XCTAssertEqual(chatProfile.appFamily, .chat)
        XCTAssertEqual(chatProfile.defaultIntent, .insert)
        XCTAssertTrue(chatProfile.enableSelectionDetection)
        XCTAssertEqual(chatProfile.retryCount, 3)
    }

    func testProfileForUnknown() {
        let profile = InsertionCompatibilityProfile.profile(for: .unknown)

        XCTAssertEqual(profile.appFamily, .native)
        XCTAssertEqual(profile.defaultIntent, .insert)
        XCTAssertTrue(profile.enableSelectionDetection)
        XCTAssertEqual(profile.retryCount, 2)
        XCTAssertTrue(profile.enableFallbackCopy)
    }

    func testProfileInitialization() {
        let profile = InsertionCompatibilityProfile(
            appFamily: .browser,
            defaultIntent: .smart,
            enableSelectionDetection: false,
            enableSmartAppend: true,
            retryCount: 5,
            retryIntervalMs: 200,
            enableFallbackCopy: false,
            requiresSpecialHandling: true,
            specialHandlingNotes: "Test notes"
        )

        XCTAssertEqual(profile.appFamily, .browser)
        XCTAssertEqual(profile.defaultIntent, .smart)
        XCTAssertFalse(profile.enableSelectionDetection)
        XCTAssertTrue(profile.enableSmartAppend)
        XCTAssertEqual(profile.retryCount, 5)
        XCTAssertEqual(profile.retryIntervalMs, 200)
        XCTAssertFalse(profile.enableFallbackCopy)
        XCTAssertTrue(profile.requiresSpecialHandling)
        XCTAssertEqual(profile.specialHandlingNotes, "Test notes")
    }

    // MARK: - InsertionPlan Tests

    func testInsertionPlanInitialization() {
        let profile = InsertionCompatibilityProfile.profile(for: .browser)
        let plan = InsertionPlan(
            intent: .insert,
            appFamily: .browser,
            profile: profile,
            steps: [.detectFrontmostApp],
            fallbackStrategy: .copyToClipboard
        )

        XCTAssertEqual(plan.intent, .insert)
        XCTAssertEqual(plan.appFamily, .browser)
        XCTAssertEqual(plan.profile.appFamily, .browser)
        XCTAssertEqual(plan.steps.count, 1)
    }

    func testInsertionPlanCreate() {
        let plan = InsertionPlan.create(intent: .insert, appFamily: .browser)

        XCTAssertEqual(plan.intent, .insert)
        XCTAssertEqual(plan.appFamily, .browser)
        XCTAssertGreaterThan(plan.steps.count, 0)
    }

    func testInsertionPlanCreateWithDifferentIntents() {
        let insertPlan = InsertionPlan.create(intent: .insert, appFamily: .browser)
        let replacePlan = InsertionPlan.create(intent: .replaceSelection, appFamily: .ide)
        let appendPlan = InsertionPlan.create(intent: .appendAfterSelection, appFamily: .chat)

        XCTAssertEqual(insertPlan.intent, .insert)
        XCTAssertEqual(replacePlan.intent, .replaceSelection)
        XCTAssertEqual(appendPlan.intent, .appendAfterSelection)
    }

    // MARK: - InsertionStep Tests

    func testGenerateStepsForBrowser() {
        let profile = InsertionCompatibilityProfile.profile(for: .browser)
        let steps = InsertionStep.generateSteps(
            intent: .insert,
            appFamily: .browser,
            profile: profile
        )

        XCTAssertGreaterThan(steps.count, 0)
        XCTAssertTrue(steps.contains { if case .detectFrontmostApp = $0 { true } else { false } })
        XCTAssertTrue(steps.contains { if case .detectSelection = $0 { true } else { false } })
        XCTAssertTrue(steps.contains { if case .focusTarget = $0 { true } else { false } })
        XCTAssertTrue(steps.contains { if case .pasteCommand = $0 { true } else { false } })
    }

    func testGenerateStepsForTerminal() {
        let profile = InsertionCompatibilityProfile.profile(for: .terminal)
        let steps = InsertionStep.generateSteps(
            intent: .insert,
            appFamily: .terminal,
            profile: profile
        )

        XCTAssertGreaterThan(steps.count, 0)
        XCTAssertTrue(steps.contains { if case .terminalPasteCommand = $0 { true } else { false } })
        XCTAssertFalse(steps.contains { if case .pasteCommand = $0 { true } else { false } })
    }

    func testGenerateStepsForIDEWithReplaceIntent() {
        let profile = InsertionCompatibilityProfile.profile(for: .ide)
        let steps = InsertionStep.generateSteps(
            intent: .replaceSelection,
            appFamily: .ide,
            profile: profile
        )

        XCTAssertGreaterThan(steps.count, 0)
        XCTAssertTrue(steps.contains { if case .replaceSelection = $0 { true } else { false } })
    }

    func testGenerateStepsWithRetryAndFallback() {
        let profile = InsertionCompatibilityProfile(
            appFamily: .browser,
            retryCount: 3,
            retryIntervalMs: 100,
            enableFallbackCopy: true
        )
        let steps = InsertionStep.generateSteps(
            intent: .insert,
            appFamily: .browser,
            profile: profile
        )

        XCTAssertTrue(steps.contains { if case .retry = $0 { true } else { false } })
        XCTAssertTrue(steps.contains { if case .fallbackCopy = $0 { true } else { false } })
    }

    func testGenerateStepsAlwaysHasRecordOutcome() {
        let profile = InsertionCompatibilityProfile.profile(for: .browser)
        let steps = InsertionStep.generateSteps(
            intent: .insert,
            appFamily: .browser,
            profile: profile
        )

        XCTAssertTrue(steps.contains { if case .recordOutcome = $0 { true } else { false } })
    }

    // MARK: - FallbackStrategy Tests

    func testFallbackStrategyCases() {
        let strategies: [FallbackStrategy] = [.copyToClipboard, .showManualPasteHint, .logError, .none]
        for strategy in strategies {
            XCTAssertTrue(strategies.contains(strategy))
        }
    }
}
