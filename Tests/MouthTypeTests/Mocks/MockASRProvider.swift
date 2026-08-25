import Foundation
@testable import MouthType

/// Mock ASR Provider - 用于端到端测试
///
/// 实现 ASRProvider 协议，返回预设的转写结果
final class MockASRProvider: ASRProvider, @unchecked Sendable {
    var isAvailable: Bool { availabilityError == nil }
    var availabilityError: Error?
    
    /// 预设的转写结果
    var mockTranscribeResult: ASRResult?
    var mockTranscribeError: Error?
    
    /// 预设的流式 segment
    var mockStreamSegments: [ASRSegment] = []
    var mockStreamError: Error?
    
    /// 记录方法调用
    private(set) var transcribeCalls: [(audioURL: URL, hotwords: [String])] = []
    private(set) var startStreamingCalls: [[String]] = []
    private(set) var stopStreamingCalls = 0
    private(set) var sendAudioCalls: [Data] = []
    
    /// 模拟延迟
    var transcribeDelay: TimeInterval = 0.1
    var streamDelay: TimeInterval = 0.05
    
    func reset() {
        availabilityError = nil
        mockTranscribeResult = nil
        mockTranscribeError = nil
        mockStreamSegments = []
        mockStreamError = nil
        transcribeCalls.removeAll()
        startStreamingCalls.removeAll()
        stopStreamingCalls = 0
        sendAudioCalls.removeAll()
    }
    
    func transcribe(audioURL: URL, hotwords: [String]) async throws -> ASRResult {
        transcribeCalls.append((audioURL, hotwords))
        
        if transcribeDelay > 0 {
            try? await Task.sleep(for: .seconds(transcribeDelay))
        }
        
        if let error = mockTranscribeError {
            throw error
        }
        
        return mockTranscribeResult ?? ASRResult(text: "模拟转写结果", language: "zh")
    }
    
    func startStreaming(hotwords: [String]) async throws -> AsyncThrowingStream<ASRSegment, Error> {
        startStreamingCalls.append(hotwords)
        
        return AsyncThrowingStream { continuation in
            Task {
                if let error = self.mockStreamError {
                    continuation.finish(throwing: error)
                    return
                }
                
                for segment in self.mockStreamSegments {
                    continuation.yield(segment)
                    if self.streamDelay > 0 {
                        try? await Task.sleep(for: .seconds(self.streamDelay))
                    }
                }
                
                continuation.finish()
            }
        }
    }
    
    func stopStreaming() async {
        stopStreamingCalls += 1
    }
    
    func sendAudio(_ pcmData: Data) async {
        sendAudioCalls.append(pcmData)
    }
}
