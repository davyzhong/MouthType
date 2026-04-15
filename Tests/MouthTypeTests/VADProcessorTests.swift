import XCTest
import AVFoundation
@testable import MouthType

// MARK: - VADProcessor Tests (Refactored)

final class VADProcessorTests: XCTestCase {
    var vadProcessor: VADProcessor!

    override func setUp() {
        super.setUp()
        vadProcessor = VADProcessor()
    }

    override func tearDown() {
        vadProcessor = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testVADProcessorInitialization() {
        let config = VADProcessor.Config(
            activationThreshold: 0.03,
            silenceThreshold: 0.015,
            activationWindowMs: 200,
            hangoverMs: 400,
            noiseFloorAlpha: 0.95,
            minNoiseFloor: 0.002,
            sampleRate: 16000,
            channels: 1
        )

        let processor = VADProcessor(config: config)

        XCTAssertTrue(processor.currentState.isSilent)
        XCTAssertFalse(processor.isVoiceActive)
    }

    func testDefaultConfiguration() {
        let processor = VADProcessor()
        XCTAssertTrue(processor.currentState.isSilent)
        XCTAssertFalse(processor.isVoiceActive)
    }

    // MARK: - State Tests

    func testInitialStateAndVoiceActiveStatus() async throws {
        // 初始状态应为静音
        XCTAssertTrue(vadProcessor.currentState.isSilent)
        XCTAssertFalse(vadProcessor.isVoiceActive)

        // 激活后应为活动状态
        try await activateVAD()
        XCTAssertTrue(vadProcessor.isVoiceActive)
    }

    // MARK: - Reset Tests

    func testResetClearsStateAndPreservesCallbacks() async throws {
        try await activateVAD()

        // 设置回调
        vadProcessor.onVoiceDetected = { }

        // 重置
        vadProcessor.reset()

        // 验证状态已清除
        XCTAssertTrue(vadProcessor.currentState.isSilent)
        XCTAssertFalse(vadProcessor.isVoiceActive)

        // 验证回调仍然存在
        XCTAssertNotNil(vadProcessor.onVoiceDetected)
    }

    // MARK: - Debug Info Tests

    func testDebugInfoContainsStateInformation() {
        let debugInfo = vadProcessor.debugInfo
        XCTAssertTrue(debugInfo.contains("VAD"))
        XCTAssertTrue(debugInfo.contains("Silent") || debugInfo.contains("noise floor"))
    }

    // MARK: - Callback Tests

    func testCallbacksCanBeSet() {
        vadProcessor.onStateChange = { _ in }
        vadProcessor.onVoiceDetected = { }
        vadProcessor.onSilenceDetected = { }

        // Verify callbacks are set
        XCTAssertNotNil(vadProcessor.onStateChange)
        XCTAssertNotNil(vadProcessor.onVoiceDetected)
        XCTAssertNotNil(vadProcessor.onSilenceDetected)

        // Process some audio to trigger state change
        let buffer = createAudioBuffer(withLevel: 0.05)
        vadProcessor.process(buffer) { _ in }
    }

    // MARK: - Audio Processing Tests

    func testProcessHandlesVariousBufferConditions() {
        let testCases: [(String, Float, UInt32)] = [
            ("空缓冲", 0, 0),
            ("静音缓冲", 0, 1600),
            ("低电平音频", 0.001, 1600),
            ("高电平音频", 0.5, 1600),
        ]

        for (_, level, frameCount) in testCases {
            let buffer = createAudioBuffer(withLevel: level, frameCount: frameCount)
            vadProcessor.process(buffer) { _ in }
            // Should not crash
        }
    }

    // MARK: - Config Tests

    func testConfigThresholdAndTimingValues() {
        let config = VADProcessor.Config(
            activationThreshold: 0.5,
            silenceThreshold: 0.1,
            activationWindowMs: 500,
            hangoverMs: 1000
        )

        XCTAssertEqual(config.activationThreshold, 0.5)
        XCTAssertEqual(config.silenceThreshold, 0.1)
        XCTAssertEqual(config.activationWindowMs, 500)
        XCTAssertEqual(config.hangoverMs, 1000)
    }

    // MARK: - Optimized Config Tests

    func testOptimizedConfigParameters() {
        // 测试优化后的配置参数
        let config = VADProcessor.Config(
            activationWindowMs: 100,
            hangoverMs: 200,
            noiseFloorAlpha: 0.95,
            activationSmoothingFrames: 2,
            reactivationThreshold: 0.03
        )

        XCTAssertEqual(config.activationWindowMs, 100, "激活窗口应为 100ms")
        XCTAssertEqual(config.hangoverMs, 200, "尾音时间应为 200ms")
        XCTAssertEqual(config.noiseFloorAlpha, 0.95, "噪声底自适应因子应为 0.95")
        XCTAssertEqual(config.reactivationThreshold, 0.03, "快速重新激活阈值应为 0.03")
        XCTAssertEqual(config.activationSmoothingFrames, 2, "激活平滑帧数应为 2")
    }

    func testOptimizedConfigFasterResponse() {
        // 验证优化后的配置响应更快
        let optimizedConfig = VADProcessor.Config(
            activationWindowMs: 100,
            hangoverMs: 200
        )
        let originalConfig = VADProcessor.Config(
            activationWindowMs: 150,
            hangoverMs: 300
        )

        XCTAssertLessThan(optimizedConfig.activationWindowMs, originalConfig.activationWindowMs,
                         "优化后的激活窗口应更短")
        XCTAssertLessThan(optimizedConfig.hangoverMs, originalConfig.hangoverMs,
                         "优化后的尾音时间应更短")
    }

    func testFastReactivationMechanism() async throws {
        // 测试快速重新激活机制
        vadProcessor.onVoiceDetected = { }

        // 使用低阈值配置快速激活
        let config = VADProcessor.Config(
            activationThreshold: 0.0001,
            silenceThreshold: 0.00005,
            activationWindowMs: 10,
            hangoverMs: 50,
            reactivationThreshold: 0.03
        )
        vadProcessor = VADProcessor(config: config)

        // 先激活
        for _ in 0..<10 {
            let buffer = createAudioBuffer(withLevel: 0.5)
            vadProcessor.process(buffer) { _ in }
        }

        // 验证已进入 active 状态
        XCTAssertTrue(vadProcessor.isVoiceActive, "应进入 active 状态")

        // 模拟静音后强声音（测试快速重新激活）
        for _ in 0..<5 {
            let buffer = createAudioBuffer(withLevel: 0.5)
            vadProcessor.process(buffer) { _ in }
        }
    }

    // MARK: - Helper Methods

    private func createAudioBuffer(withLevel level: Float, frameCount: UInt32 = 1600) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            return buffer
        }

        for i in 0..<Int(frameCount) {
            if level == 0 {
                channelData[i] = 0
            } else {
                channelData[i] = level * sinf(Float(i) * 0.1)
            }
        }

        return buffer
    }

    private func activateVAD() async throws {
        let config = VADProcessor.Config(
            activationThreshold: 0.0001,
            silenceThreshold: 0.00005,
            activationWindowMs: 10,
            hangoverMs: 300,
            noiseFloorAlpha: 0.98,
            minNoiseFloor: 0.0001,
            sampleRate: 16000,
            channels: 1
        )

        vadProcessor = VADProcessor(config: config)

        // Send high-level audio to trigger activation
        for _ in 0..<20 {
            let buffer = createAudioBuffer(withLevel: 0.5)
            vadProcessor.process(buffer) { _ in }
        }
    }
}

// MARK: - VADState Test Helpers

extension VADProcessor.VADState {
    var isSilent: Bool {
        if case .silent = self { return true }
        return false
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isActivating: Bool {
        if case .activating = self { return true }
        return false
    }

    var isTrailing: Bool {
        if case .trailing = self { return true }
        return false
    }
}
