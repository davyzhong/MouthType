import Foundation
import AppKit
@testable import MouthType

/// Mock 粘贴服务 - 用于端到端测试
///
/// 记录所有粘贴调用，模拟成功/失败场景
final class MockPasteService: @unchecked Sendable {
    
    /// 记录的粘贴调用
    struct PasteCall: Sendable {
        let text: String
        let intent: InsertionIntent?
        let appFamily: AppFamily?
        let timestamp: Date
    }
    
    private(set) var pasteCalls: [PasteCall] = []
    private(set) var accessibilityCheckCalls = 0
    
    /// 模拟权限状态
    var mockAccessibilityGranted = true
    
    /// 模拟粘贴结果
    var shouldFailPaste = false
    var mockPasteError: Error?
    
    /// 模拟延迟
    var pasteDelay: TimeInterval = 0.05
    
    func reset() {
        pasteCalls.removeAll()
        accessibilityCheckCalls = 0
        mockAccessibilityGranted = true
        shouldFailPaste = false
        mockPasteError = nil
        pasteDelay = 0.05
    }
    
    func checkAccessibility() -> Bool {
        accessibilityCheckCalls += 1
        return mockAccessibilityGranted
    }
    
    func paste(text: String) async throws {
        if !mockAccessibilityGranted {
            throw PasteService.PasteError.accessibilityNotGranted
        }
        
        if pasteDelay > 0 {
            try? await Task.sleep(for: .seconds(pasteDelay))
        }
        
        if shouldFailPaste {
            throw mockPasteError ?? PasteService.PasteError.appleScriptFailed("模拟粘贴失败")
        }
        
        pasteCalls.append(PasteCall(
            text: text,
            intent: nil,
            appFamily: nil,
            timestamp: Date()
        ))
    }
    
    func paste(text: String, intent: InsertionIntent) async throws -> InsertionOutcomeMode {
        if !mockAccessibilityGranted {
            throw PasteService.PasteError.accessibilityNotGranted
        }
        
        if pasteDelay > 0 {
            try? await Task.sleep(for: .seconds(pasteDelay))
        }
        
        if shouldFailPaste {
            throw mockPasteError ?? PasteService.PasteError.appleScriptFailed("模拟粘贴失败")
        }
        
        let appFamily = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
                    continuation.resume(returning: AppFamily.unknown)
                    return
                }
                continuation.resume(returning: AppFamily.detect(appName: appName))
            }
        }
        
        pasteCalls.append(PasteCall(
            text: text,
            intent: intent,
            appFamily: appFamily,
            timestamp: Date()
        ))
        
        return .inserted
    }
}
