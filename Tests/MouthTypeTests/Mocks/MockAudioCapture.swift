import Foundation
@testable import MouthType

/// Mock 音频捕获 - 用于端到端测试
///
/// 模拟 AudioCapture 的行为，无需真实麦克风
final class MockAudioCapture: @unchecked Sendable {
    var onAudioLevel: ((Float) -> Void)?
    
    private var isRecording = false
    private var isStreaming = false
    private var recordedData: Data?
    private var streamingHandler: ((Data) -> Void)?
    private var recordingURL: URL?
    
    /// 模拟录制返回的音频文件 URL
    var mockRecordingURL: URL?
    
    /// 模拟流式音频的 PCM 数据队列
    var mockStreamPCMData: [Data] = []
    
    /// 记录方法调用
    private(set) var startRecordingCalls = 0
    private(set) var stopRecordingCalls = 0
    private(set) var startStreamingCalls = 0
    private(set) var stopStreamingCalls = 0
    
    /// 模拟错误
    var shouldFailStartRecording = false
    var shouldFailStartStreaming = false
    var mockStartRecordingError: Error?
    var mockStartStreamingError: Error?
    
    func reset() {
        isRecording = false
        isStreaming = false
        recordedData = nil
        streamingHandler = nil
        recordingURL = nil
        startRecordingCalls = 0
        stopRecordingCalls = 0
        startStreamingCalls = 0
        stopStreamingCalls = 0
        shouldFailStartRecording = false
        shouldFailStartStreaming = false
        mockStartRecordingError = nil
        mockStartStreamingError = nil
    }
}

// MARK: - AudioCapture Protocol

extension MockAudioCapture {
    func startRecording() throws -> URL {
        startRecordingCalls += 1
        
        if shouldFailStartRecording {
            throw mockStartRecordingError ?? NSError(domain: "MockAudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "模拟录音失败"])
        }
        
        isRecording = true
        
        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let url = mockRecordingURL ?? tempDir.appendingPathComponent("mock_recording_\(UUID().uuidString).wav")
        recordingURL = url
        
        // 写入模拟音频数据（空 WAV 头）
        let wavHeader = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
                              0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
                              0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
                              0x80, 0x3E, 0x00, 0x00, 0x00, 0x7D, 0x00, 0x00,
                              0x02, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61,
                              0x00, 0x00, 0x00, 0x00])
        try? wavHeader.write(to: url)
        
        return url
    }
    
    func stopRecording() -> URL? {
        stopRecordingCalls += 1
        isRecording = false
        let url = recordingURL
        recordingURL = nil
        return url ?? mockRecordingURL
    }
    
    func startStreaming(handler: @escaping (Data) -> Void) throws {
        startStreamingCalls += 1
        
        if shouldFailStartStreaming {
            throw mockStartStreamingError ?? NSError(domain: "MockAudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "模拟流式失败"])
        }
        
        isStreaming = true
        streamingHandler = handler
        
        // 模拟发送音频数据
        Task { [weak self] in
            for pcmData in self?.mockStreamPCMData ?? [] {
                guard let self = self, self.isStreaming else { break }
                handler(pcmData)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    
    func stopStreaming() {
        stopStreamingCalls += 1
        isStreaming = false
        streamingHandler = nil
    }
    
    func simulateAudioLevel(_ level: Float) {
        onAudioLevel?(level)
    }
    
    func simulateStreamData(_ data: Data) {
        guard isStreaming else { return }
        streamingHandler?(data)
    }
}
