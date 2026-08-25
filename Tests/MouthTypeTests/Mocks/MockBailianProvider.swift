import Foundation
@testable import MouthType

/// Mock Bailian Provider - 用于端到端测试
///
/// 模拟 BailianStreamingProvider 的 WebSocket 交互
final class MockBailianProvider: @unchecked Sendable {
    var isAvailable: Bool = true
    
    /// 预设的流式 segment
    var mockSegments: [ASRSegment] = []
    var mockError: Error?
    
    /// 记录方法调用
    private(set) var startStreamingCalls: [[String]] = []
    private(set) var stopStreamingCalls = 0
    private(set) var sendAudioCalls: [Data] = []
    
    /// 模拟延迟
    var startDelay: TimeInterval = 0.05
    var segmentDelay: TimeInterval = 0.05
    
    private var streamContinuation: AsyncThrowingStream<ASRSegment, Error>.Continuation?
    
    func reset() {
        isAvailable = true
        mockSegments.removeAll()
        mockError = nil
        startStreamingCalls.removeAll()
        stopStreamingCalls = 0
        sendAudioCalls.removeAll()
        streamContinuation = nil
    }
    
    func startStreaming(hotwords: [String]) async throws -> AsyncThrowingStream<ASRSegment, Error> {
        startStreamingCalls.append(hotwords)
        
        if startDelay > 0 {
            try? await Task.sleep(for: .seconds(startDelay))
        }
        
        if let error = mockError {
            throw error
        }
        
        return AsyncThrowingStream { continuation in
            self.streamContinuation = continuation
            
            Task {
                for segment in self.mockSegments {
                    continuation.yield(segment)
                    if self.segmentDelay > 0 {
                        try? await Task.sleep(for: .seconds(self.segmentDelay))
                    }
                }
                continuation.finish()
            }
        }
    }
    
    func stopStreaming() async {
        stopStreamingCalls += 1
        streamContinuation?.finish()
        streamContinuation = nil
    }
    
    func sendAudio(_ pcmData: Data) async {
        sendAudioCalls.append(pcmData)
    }
}
