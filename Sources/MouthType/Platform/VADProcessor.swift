import AVFoundation
import Foundation
import os

private let vadLog = Logger(subsystem: "com.mouthtype", category: "VAD")

/// Multi-state Voice Activity Detector with adaptive noise floor tracking
///
/// States:
/// - `.silent`: Waiting for voice, adaptive noise floor tracking
/// - `.activating`: Building confidence, ring buffer pre-roll
/// - `.active`: Voice detected, streaming audio
/// - `.trailing`: Voice ended, hangover period for re-activation
///
/// Thread safety: Designed for single-threaded audio processing queue
final class VADProcessor: @unchecked Sendable {
    // MARK: - Configuration

    struct Config: Sendable {
        /// RMS threshold for voice detection (0.0-1.0)
        var activationThreshold: Float = 0.02

        /// RMS threshold for silence detection (hysteresis)
        var silenceThreshold: Float = 0.01

        /// Minimum activation duration before transitioning to active (ms)
        var activationWindowMs: Int = 100

        /// Hangover time after silence detected (ms)
        /// 优化：从 300ms 降低到 200ms，减少尾音等待时间
        var hangoverMs: Int = 200

        /// Noise floor smoothing factor (0.0-1.0, higher = slower adaptation)
        var noiseFloorAlpha: Float = 0.95

        /// Minimum noise floor to prevent over-adaptation
        var minNoiseFloor: Float = 0.001

        /// Sample rate of incoming audio
        var sampleRate: Double = 16000

        /// Channels in audio stream
        var channels: Int = 1

        /// 优化：添加激活平滑因子，需要连续多帧超过阈值才激活
        var activationSmoothingFrames: Int = 2

        /// 优化：添加尾音快速切断阈值，高于此值立即返回 active 状态
        var reactivationThreshold: Float = 0.03
    }

    // MARK: - State

    enum VADState: Sendable {
        case silent
        case activating(activatingFrames: Int)
        case active
        case trailing(trailingFrames: Int)
    }

    private var state: VADState = .silent

    // MARK: - Adaptive Noise Floor

    private var noiseFloor: Float = 0.01
    private var noiseFloorInitialized = false

    // MARK: - Ring Buffer

    private var ringBuffer: [Float] = []
    private var ringBufferCapacity: Int

    // MARK: - Frame Tracking

    private var totalFrames: Int = 0
    private var activationFrameCount: Int = 0
    private var trailingFrameCount: Int = 0

    // MARK: - Callbacks

    var onStateChange: (@Sendable (VADState) -> Void)?
    var onVoiceDetected: (@Sendable () -> Void)?
    var onSilenceDetected: (@Sendable () -> Void)?

    // MARK: - Audio Format

    private let samplesPerFrame: Int
    private let framesPerSecond: Double

    // MARK: - Initialization

    init(config: Config = Config()) {
        self.config = config

        // Calculate frame timing
        self.framesPerSecond = config.sampleRate / Double(config.channels)
        self.samplesPerFrame = Int(config.sampleRate / 100.0) // 10ms frames

        // Ring buffer for pre-roll (activation window duration)
        self.ringBufferCapacity = Int(Double(config.activationWindowMs) / 10.0)

        vadLog.debug("VAD initialized: threshold=\(config.activationThreshold), hangover=\(config.hangoverMs)ms")
    }

    private let config: Config

    // MARK: - Public API

    /// Process audio buffer and return whether to emit audio
    /// - Parameters:
    ///   - buffer: PCM audio buffer (32-bit float, mono)
    ///   - shouldEmit: Closure to call with audio chunk if voice activity detected
    func process(_ buffer: AVAudioPCMBuffer, shouldEmit: @Sendable (Data) -> Void) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // Process in 10ms chunks
        let chunkSize = samplesPerFrame
        var offset = 0

        while offset < frameLength {
            let remaining = frameLength - offset
            let currentChunkSize = min(chunkSize, remaining)

            // Extract chunk and calculate RMS
            var chunkRMS: Float = 0
            for i in 0..<currentChunkSize {
                let sample = channelData[offset + i]
                chunkRMS += sample * sample
            }
            chunkRMS = sqrt(chunkRMS / Float(currentChunkSize))

            // Update adaptive noise floor (only in silent state)
            if case .silent = state {
                updateNoiseFloor(chunkRMS)
            }

            totalFrames += 1

            // Process state machine
            let normalizedLevel = chunkRMS / max(noiseFloor, config.minNoiseFloor)
            processFrame(level: normalizedLevel, rawLevel: chunkRMS, shouldEmit: shouldEmit)

            offset += currentChunkSize
        }
    }

    /// Reset VAD state for new recording session
    func reset() {
        state = .silent
        noiseFloor = 0.01
        noiseFloorInitialized = false
        ringBuffer.removeAll()
        totalFrames = 0
        activationFrameCount = 0
        trailingFrameCount = 0
        vadLog.debug("VAD reset")
    }

    /// Current VAD state
    var currentState: VADState { state }

    /// Whether currently in voice-active state (including trailing)
    var isVoiceActive: Bool {
        switch state {
        case .silent, .activating: false
        case .active, .trailing: true
        }
    }

    // MARK: - Private Methods

    private func updateNoiseFloor(_ level: Float) {
        if !noiseFloorInitialized {
            noiseFloor = max(level, config.minNoiseFloor)
            noiseFloorInitialized = true
            vadLog.debug("Noise floor initialized: \(self.noiseFloor)")
        } else {
            // Exponential moving average
            let newFloor = noiseFloor * config.noiseFloorAlpha + level * (1 - config.noiseFloorAlpha)
            noiseFloor = max(newFloor, config.minNoiseFloor)
        }
    }

    private func processFrame(level: Float, rawLevel: Float, shouldEmit: (Data) -> Void) {
        let oldState = state

        switch state {
        case .silent:
            if level > config.activationThreshold {
                // Start activation
                state = .activating(activatingFrames: 1)
                activationFrameCount = 1
                ringBuffer.removeAll()
                vadLog.debug("VAD: silent -> activating (level=\(level))")
            }

        case .activating(let frames):
            // Store in ring buffer
            ringBuffer.append(rawLevel)

            if level > config.silenceThreshold {
                activationFrameCount = frames + 1
                let requiredFrames = requiredActivationFrames()
                if activationFrameCount >= requiredFrames {
                    state = .active
                    onVoiceDetected?()
                    vadLog.debug("VAD: activating -> active (confidence=\(self.activationFrameCount)/\(requiredFrames))")
                } else {
                    state = .activating(activatingFrames: activationFrameCount)
                }
            } else {
                // Silence during activation - reset
                state = .silent
                ringBuffer.removeAll()
                vadLog.debug("VAD: activating -> silent (premature silence)")
            }

        case .active:
            if level < config.silenceThreshold {
                // Start trailing hangover
                trailingFrameCount = 0
                state = .trailing(trailingFrames: 0)
                vadLog.debug("VAD: active -> trailing (hangover starts)")
            }

        case .trailing(let frames):
            trailingFrameCount = frames + 1
            let maxTrailingFrames = requiredHangoverFrames()

            // 优化：如果声音突然增大，立即返回 active 状态（快速响应尾音后的语音）
            if level > config.reactivationThreshold {
                state = .active
                onVoiceDetected?()
                vadLog.debug("VAD: trailing -> active (strong voice returned, level=\(level))")
            } else if level > config.activationThreshold {
                // Voice returned during trailing - go back to active
                state = .active
                onVoiceDetected?()
                vadLog.debug("VAD: trailing -> active (voice returned)")
            } else if trailingFrameCount >= maxTrailingFrames {
                // Hangover expired - go to silent
                state = .silent
                onSilenceDetected?()
                vadLog.debug("VAD: trailing -> silent (hangover expired)")
            } else {
                state = .trailing(trailingFrames: trailingFrameCount)
            }
        }

        // Notify state change
        if !statesEqual(oldState, state) {
            onStateChange?(state)
        }
    }

    private func statesEqual(_ a: VADState, _ b: VADState) -> Bool {
        switch (a, b) {
        case (.silent, .silent), (.active, .active):
            return true
        case (.activating(let x), .activating(let y)):
            return x == y
        case (.trailing(let x), .trailing(let y)):
            return x == y
        default:
            return false
        }
    }

    private func requiredActivationFrames() -> Int {
        Int(ceil(Double(config.activationWindowMs) / 10.0))
    }

    private func requiredHangoverFrames() -> Int {
        Int(ceil(Double(config.hangoverMs) / 10.0))
    }

    // MARK: - Debug Info

    /// Current debug information
    var debugInfo: String {
        switch state {
        case .silent:
            return String(format: "VAD: Silent (noise floor: %.4f)", noiseFloor)
        case .activating(let frames):
            let required = requiredActivationFrames()
            return "VAD: Activating \(frames)/\(required)"
        case .active:
            return "VAD: Active"
        case .trailing(let frames):
            let max = requiredHangoverFrames()
            return "VAD: Trailing \(frames)/\(max)"
        }
    }
}
