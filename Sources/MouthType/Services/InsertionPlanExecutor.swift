import AppKit
import ApplicationServices
import Foundation
import os

private let insertionLog = RedactedLogger(subsystem: "com.mouthtype", category: "Insertion")

/// 插入计划执行器
///
/// 根据插入计划执行文本插入操作
///
/// Thread safety: Designed for async/await usage with MainActor
final class InsertionPlanExecutor: @unchecked Sendable {
    private let pasteboard = NSPasteboard.general
    private var previousClipboardContents: String?

    /// 检查辅助功能权限
    static func checkAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)
    }

    /// 请求辅助功能权限
    static func promptAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    /// 检查输入监听权限
    static func checkInputMonitoring() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// 请求输入监听权限
    static func promptInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    /// 打开辅助功能设置
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 打开输入监听设置
    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 执行插入计划
    /// - Parameters:
    ///   - plan: 插入计划
    ///   - text: 要插入的文本
    /// - Returns: 插入结果
    func execute(plan: InsertionPlan, text: String) async throws -> InsertionOutcomeMode {
        insertionLog.info("Executing insertion plan: intent=\(plan.intent.displayName), appFamily=\(plan.appFamily.rawValue)")

        // 保存之前的剪贴板内容
        previousClipboardContents = pasteboard.string(forType: .string)

        // 设置新内容
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 短暂延迟确保剪贴板就绪
        try? await Task.sleep(for: .milliseconds(50))

        // 检测前台应用
        guard let appInfo = await detectFrontmostApp() else {
            throw InsertionError.accessibilityNotGranted
        }

        insertionLog.info("Frontmost app: \(appInfo.name) (family: \(appInfo.family.rawValue))")

        // 检测是否有选中
        let hasSelection = plan.profile.enableSelectionDetection ? await detectSelection() : false
        insertionLog.trace("Has selection: \(hasSelection)")

        // 执行插入步骤
        var outcome: InsertionOutcomeMode = .failed(reason: "未执行")

        for step in plan.steps {
            switch step {
            case .detectFrontmostApp:
                // 已完成
                break

            case .detectSelection:
                // 已完成
                break

            case .focusTarget:
                // macOS 辅助功能会自动聚焦
                break

            case .pasteCommand:
                outcome = await executePasteCommand(isTerminal: false)

            case .terminalPasteCommand:
                outcome = await executePasteCommand(isTerminal: true)

            case .replaceSelection:
                outcome = await executeReplaceSelection()

            case .appendCommand:
                outcome = await executeAppendCommand()

            case .wait(let duration):
                try? await Task.sleep(for: .seconds(duration))

            case .retry(let maxAttempts, let delay):
                if case .failed = outcome {
                    outcome = await retryPaste(maxAttempts: maxAttempts, delay: delay, isTerminal: plan.appFamily == .terminal)
                }

            case .fallbackCopy:
                if case .failed = outcome {
                    outcome = .copied
                    insertionLog.warning("Fallback to clipboard copy")
                }

            case .recordOutcome(let recordedOutcome):
                // 记录最终结果
                insertionLog.info("Insertion outcome: \(recordedOutcome.displayName)")
                outcome = recordedOutcome
            }

            // 如果已成功，提前退出
            if outcome.isSuccess {
                break
            }
        }

        // 恢复之前的剪贴板内容
        try? await Task.sleep(for: .milliseconds(200))
        restorePreviousClipboard()

        return outcome
    }

    // MARK: - Private Methods

    private func detectFrontmostApp() async -> (name: String, family: AppFamily)? {
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return nil
        }
        let appFamily = AppFamily.detect(appName: appName)
        return (appName, appFamily)
    }

    private func detectSelection() async -> Bool {
        // 通过辅助功能检测是否有选中文本
        let script = """
        tell application "System Events"
            try
                set selectedText to value of attribute "AXSelectedText" of application process (name of first application process whose frontmost is true)
                return selectedText is not missing value and (selectedText as string) is not ""
            on error
                return false
            end try
        end tell
        """

        return await executeAppleScriptBool(script)
    }

    private func executePasteCommand(isTerminal: Bool) async -> InsertionOutcomeMode {
        guard Self.checkAccessibility() else {
            return .failed(reason: "辅助功能权限不足")
        }

        let script: String
        if isTerminal {
            script = """
            tell application "System Events"
                keystroke "v" using {command down, shift down}
            end tell
            """
        } else {
            script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        }

        do {
            try await executeAppleScript(script)
            return .inserted
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    private func executeReplaceSelection() async -> InsertionOutcomeMode {
        // 先删除选中文本，再粘贴
        let deleteScript = """
        tell application "System Events"
            keystroke delete
        end tell
        """

        do {
            try await executeAppleScript(deleteScript)
            try? await Task.sleep(for: .milliseconds(50))
            return await executePasteCommand(isTerminal: false)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    private func executeAppendCommand() async -> InsertionOutcomeMode {
        // 移动到行尾再粘贴
        let moveToEndScript = """
        tell application "System Events"
            keystroke home using command down
            keystroke end using command down
        end tell
        """

        do {
            try await executeAppleScript(moveToEndScript)
            try? await Task.sleep(for: .milliseconds(50))
            return await executePasteCommand(isTerminal: false)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    private func retryPaste(maxAttempts: Int, delay: TimeInterval, isTerminal: Bool) async -> InsertionOutcomeMode {
        for attempt in 1...maxAttempts {
            insertionLog.trace("Retry attempt \(attempt)/\(maxAttempts)")
            try? await Task.sleep(for: .seconds(delay))

            let outcome = await executePasteCommand(isTerminal: isTerminal)
            if outcome.isSuccess {
                return outcome
            }
        }

        return .failed(reason: "重试\(maxAttempts)次后仍失败")
    }

    private func restorePreviousClipboard() {
        pasteboard.clearContents()
        if let previous = previousClipboardContents {
            pasteboard.setString(previous, forType: .string)
        }
    }

    private func executeAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                let script = NSAppleScript(source: source)
                var error: NSDictionary?
                script?.executeAndReturnError(&error)

                if let error {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
                    continuation.resume(throwing: InsertionError.appleScriptFailed(msg))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func executeAppleScriptBool(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let script = NSAppleScript(source: source)
                var error: NSDictionary?
                let result = script?.executeAndReturnError(&error)

                if let boolResult = result?.booleanValue {
                    continuation.resume(returning: boolResult)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

enum InsertionError: LocalizedError {
    case appleScriptFailed(String)
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let msg): "粘贴失败：\(msg)"
        case .accessibilityNotGranted: "需要辅助功能权限"
        }
    }
}
