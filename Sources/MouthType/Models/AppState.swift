import SwiftUI

enum DictationState: Equatable {
    case idle
    case listening
    case recording
    case streaming(String)
    case processing
    case aiProcessing
    case error(String)
}

@Observable
final class AppState {
    static let shared = AppState()

    var dictationState: DictationState = .idle
    var streamingText: String = ""
    /// 音频级别 (0.0 - 1.0)
    /// 使用显式方法设置以确保值在有效范围内
    private var _audioLevel: Float = 0
    var audioLevel: Float { _audioLevel }
    var lastTranscription: String = ""
    var errorMessage: String = ""
    var errorRecoveryTimer: Timer?

    /// 设置音频级别，自动限制在 0.0 - 1.0 范围内
    @MainActor
    func setAudioLevel(_ level: Float) {
        _audioLevel = max(0, min(1, level))
    }

    var isRecording: Bool {
        switch dictationState {
        case .listening, .recording, .streaming:
            return true
        default:
            return false
        }
    }

    /// 进入错误状态时自动启动恢复定时器
    @MainActor
    func transitionToError(_ message: String) {
        // 清空流式文本和音频级别
        streamingText = ""
        audioLevel = 0

        errorMessage = message
        dictationState = .error(message)

        // 3 秒后自动恢复到 idle，避免永久卡在错误状态
        errorRecoveryTimer?.invalidate()
        errorRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.recoverFromError()
            }
        }
    }

    /// 手动触发恢复（例如用户再次按下热键）
    @MainActor
    func recoverFromError() {
        // 只在错误状态下才执行恢复
        guard case .error = dictationState else { return }

        errorRecoveryTimer?.invalidate()
        errorRecoveryTimer = nil
        transition(to: .idle)
    }

    @MainActor
    func transition(to state: DictationState) {
        // 离开错误状态时取消恢复定时器
        if case .error = dictationState {
            errorRecoveryTimer?.invalidate()
            errorRecoveryTimer = nil
        }

        switch state {
        case .idle:
            streamingText = ""
            audioLevel = 0
            errorMessage = ""
        case .streaming(let text):
            streamingText = text
        case .processing, .aiProcessing:
            // 切换到处理状态时清空流式文本
            streamingText = ""
        case .error(let msg):
            errorMessage = msg
        default:
            break
        }
        dictationState = state
    }
}
