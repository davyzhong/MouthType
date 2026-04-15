import AppKit
import ApplicationServices
import Foundation

/// PasteService - 粘贴服务
///
/// 提供文本粘贴功能，支持智能插入计划
final class PasteService: @unchecked Sendable {
    enum PasteError: LocalizedError {
        case appleScriptFailed(String)
        case accessibilityNotGranted

        var errorDescription: String? {
            switch self {
            case .appleScriptFailed(let msg): "粘贴失败：\(msg)"
            case .accessibilityNotGranted: "需要辅助功能权限"
            }
        }
    }

    private let planExecutor = InsertionPlanExecutor()
    private let pasteboard = NSPasteboard.general
    private var previousClipboardContents: String?

    /// Check if accessibility permission is granted
    static func checkAccessibility() -> Bool {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.accessibilityGranted
        }
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)
    }

    /// Prompt user to grant accessibility permission
    static func promptAccessibility() {
        guard !UITestConfiguration.current.isEnabled else {
            return
        }
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    static func checkInputMonitoring() -> Bool {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.inputMonitoringGranted
        }
        // macOS 15.0+ 使用新 API
        if #available(macOS 15.0, *) {
            return CGPreflightListenEventAccess()
        } else {
            // 旧版本 macOS 默认允许
            return true
        }
    }

    /// Prompt user to grant input monitoring permission
    static func promptInputMonitoring() {
        guard !UITestConfiguration.current.isEnabled else {
            return
        }
        // macOS 15.0+ 先尝试请求权限
        if #available(macOS 15.0, *) {
            let granted = CGRequestListenEventAccess()
            // 如果用户拒绝或取消，直接打开设置页面
            if !granted {
                openInputMonitoringSettings()
            }
        } else {
            // 旧版本 macOS 直接打开设置
            openInputMonitoringSettings()
        }
    }

    static func openAccessibilitySettings() {
        guard !UITestConfiguration.current.isEnabled else {
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func openInputMonitoringSettings() {
        guard !UITestConfiguration.current.isEnabled else {
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Paste text to the frontmost application via clipboard + Cmd+V
    func paste(text: String) async throws {
        guard Self.checkAccessibility() else {
            throw PasteError.accessibilityNotGranted
        }

        // 使用智能插入计划
        let plan = InsertionPlan.create(intent: .smart, appFamily: .native)
        _ = try await planExecutor.execute(plan: plan, text: text)
    }

    /// Paste with explicit intent
    func paste(text: String, intent: InsertionIntent) async throws -> InsertionOutcomeMode {
        guard Self.checkAccessibility() else {
            throw PasteError.accessibilityNotGranted
        }

        // 检测前台应用家族
        let appFamily = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
                    continuation.resume(returning: AppFamily.unknown)
                    return
                }
                continuation.resume(returning: AppFamily.detect(appName: appName))
            }
        }

        let plan = InsertionPlan.create(intent: intent, appFamily: appFamily)
        return try await planExecutor.execute(plan: plan, text: text)
    }
}
