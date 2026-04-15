import Foundation

// MARK: - ASR Provider Protocol

@preconcurrency protocol ASRProvider: Sendable {
    /// One-shot transcription (for tap mode)
    func transcribe(audioURL: URL, hotwords: [String]) async throws -> ASRResult

    /// Start streaming transcription (for hold mode)
    /// Returns an async stream of transcription segments
    func startStreaming(hotwords: [String]) async throws -> AsyncThrowingStream<ASRSegment, Error>

    /// Stop streaming
    func stopStreaming() async

    /// Send audio chunk during streaming
    func sendAudio(_ pcmData: Data) async

    /// Check if provider is available (binary installed, API key set, etc.)
    var isAvailable: Bool { get }
}

// MARK: - Result Types

struct ASRResult: Sendable {
    let text: String
    let language: String?

    /// 转换为简体中文后的结果
    var simplifiedText: String {
        ChineseConverter.shared.toSimplified(text)
    }
}

struct ASRSegment: Sendable {
    let text: String
    let isFinal: Bool
    let startTime: TimeInterval
    let endTime: TimeInterval

    /// 转换为简体中文后的文本
    var simplifiedText: String {
        ChineseConverter.shared.toSimplified(text)
    }
}

// MARK: - Provider Type

enum ASRProviderType: String, CaseIterable, Sendable {
    case localWhisper = "Local Whisper (whisper.cpp)"
    case localParaformer = "Local Paraformer (中文最佳)"
    case bailianStreaming = "Aliyun Bailian Streaming (Cloud)"
    case bailian = "Aliyun Bailian (Cloud)"

    var displayName: String {
        switch self {
        case .localWhisper: "本地 Whisper (whisper.cpp)"
        case .localParaformer: "本地 Paraformer (中文最佳)"
        case .bailianStreaming: "百炼流式 (云端，中文推荐)"
        case .bailian: "百炼云端 (回退)"
        }
    }
}
