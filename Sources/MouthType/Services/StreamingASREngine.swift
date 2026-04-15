import Foundation
import os

private let streamingLog = Logger(subsystem: "com.mouthtype", category: "StreamingASR")

/// 低延迟流式 ASR 引擎
///
/// 使用滑动窗口和重叠拼接算法实现低延迟转写：
/// - 滑动窗口：每 100ms 处理一个窗口（1600 样本 @ 16kHz）
/// - 重叠拼接：相邻窗口重叠 50%，避免边界信息丢失
/// - 部分结果：每个窗口立即返回转写，不等待完整语句
final class StreamingASREngine: @unchecked Sendable {
    // MARK: - Configuration

    struct Config: Sendable {
        /// 窗口时长（毫秒）
        var windowSizeMs: Int = 400

        /// 窗口步进时长（毫秒）- 决定重叠比例
        var windowStepMs: Int = 100

        /// 采样率
        var sampleRate: Int = 16000

        /// 是否启用重叠拼接
        var enableOverlapAdd: Bool = true

        /// 最小激活能量阈值
        var minEnergyThreshold: Float = 0.001
    }

    // MARK: - State

    private var config: Config
    private var audioBuffer: [Float] = []
    private var processThread: Thread?
    private var isRunning = false
    private var shutdownRequested = false

    // 滑动窗口参数
    private var windowSize: Int       // 窗口样本数
    private var windowStep: Int       // 步进样本数
    private var overlapSize: Int      // 重叠样本数

    // 回调
    private var resultCallback: (@Sendable (ASRSegment) -> Void)?
    private var errorCallback: (@Sendable (Error) -> Void)?

    // MARK: - Initialization

    init(config: Config = Config()) {
        self.config = config

        // 计算窗口参数
        self.windowSize = Int(Double(config.sampleRate) * Double(config.windowSizeMs) / 1000.0)
        self.windowStep = Int(Double(config.sampleRate) * Double(config.windowStepMs) / 1000.0)
        self.overlapSize = (config.enableOverlapAdd) ? (windowSize - windowStep) : 0

        let overlapPercent = Double(overlapSize) / Double(windowSize) * 100
        let overlapStr = String(format: "%.1f", overlapPercent)
        let ws = windowSize
        let step = windowStep
        let ov = overlapSize
        streamingLog.debug("""
        StreamingASREngine initialized:
          - Window: \(config.windowSizeMs)ms (\(ws) samples)
          - Step: \(config.windowStepMs)ms (\(step) samples)
          - Overlap: \(ov) samples (\(overlapStr)%)
        """)
    }

    // MARK: - Public API

    /// 启动流式引擎
    /// - Parameter callback: 接收转写结果的回调
    func start(resultCallback: @escaping @Sendable (ASRSegment) -> Void) {
        guard !isRunning else {
            streamingLog.warning("Engine already running")
            return
        }

        self.resultCallback = resultCallback
        self.isRunning = true
        self.shutdownRequested = false
        self.audioBuffer.removeAll()
        self.audioBuffer.reserveCapacity(windowSize * 2)

        streamingLog.info("Streaming engine started")
    }

    /// 停止流式引擎
    func stop() {
        guard isRunning else { return }

        self.isRunning = false
        self.shutdownRequested = true
        self.resultCallback = nil

        streamingLog.info("Streaming engine stopped")
    }

    /// 接收音频数据
    /// - Parameter pcmData: PCM Int16 音频数据
    func appendAudio(_ pcmData: Data) {
        guard isRunning else { return }

        // 将 Int16 PCM 转换为 Float 样本
        let sampleCount = pcmData.count / 2
        var floatSamples: [Float] = []
        floatSamples.reserveCapacity(sampleCount)

        pcmData.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Float(int16Ptr[i]) / 32768.0
                floatSamples.append(sample)
            }
        }

        // 添加到缓冲
        audioBuffer.append(contentsOf: floatSamples)

        // 处理可用窗口
        processAvailableWindows()
    }

    /// 强制刷新剩余缓冲
    /// - Returns: 最后一段转写结果
    func flush() -> ASRSegment? {
        guard isRunning, !audioBuffer.isEmpty else { return nil }

        // 处理剩余缓冲（可能不足一个完整窗口）
        if audioBuffer.count >= windowSize / 2 {
            // 至少有半个窗口的数据，进行处理
            let window = Array(audioBuffer)
            let segment = processWindow(window, isFinal: true)
            audioBuffer.removeAll()
            return segment
        }

        audioBuffer.removeAll()
        return nil
    }

    /// 重置引擎状态
    func reset() {
        audioBuffer.removeAll()
        streamingLog.debug("Streaming engine reset")
    }

    // MARK: - Private Processing

    private func processAvailableWindows() {
        while audioBuffer.count >= windowStep {
            // 提取窗口
            let window = Array(audioBuffer.prefix(windowSize))

            // 处理窗口
            let segment = processWindow(window, isFinal: false)
            resultCallback?(segment)

            // 移动缓冲（步进）
            audioBuffer.removeFirst(windowStep)
        }
    }

    private func processWindow(_ window: [Float], isFinal: Bool) -> ASRSegment {
        // 检查能量阈值
        let energy = calculateEnergy(window)
        guard energy > config.minEnergyThreshold else {
            // 静音窗口，返回空结果
            return ASRSegment(text: "", isFinal: isFinal, startTime: 0, endTime: 0)
        }

        // 应用汉宁窗（减少边界效应）
        let windowed = applyHanningWindow(window)

        // TODO: 实际的 ASR 推理
        // 这里应该调用 sherpa-onnx 或其他 ASR 引擎
        // 当前返回模拟结果用于测试

        let mockText = generateMockTranscription(windowed)

        return ASRSegment(
            text: mockText,
            isFinal: isFinal,
            startTime: 0,
            endTime: Double(window.count) / Double(config.sampleRate)
        )
    }

    private func calculateEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sum / Float(samples.count)
    }

    private func applyHanningWindow(_ samples: [Float]) -> [Float] {
        guard config.enableOverlapAdd else { return samples }

        let N = Double(samples.count)
        var windowed: [Float] = []
        windowed.reserveCapacity(samples.count)

        for (i, sample) in samples.enumerated() {
            let hanning = 0.5 * (1 - cos(2.0 * .pi * Double(i) / N))
            windowed.append(sample * Float(hanning))
        }

        return windowed
    }

    private func generateMockTranscription(_ samples: [Float]) -> String {
        // 模拟转写结果（占位符）
        // 实际实现需要调用 ASR 引擎
        let energy = calculateEnergy(samples)
        if energy > 0.01 {
            return "测试文本"
        }
        return ""
    }

    // MARK: - Debug Info

    var debugInfo: String {
        """
        StreamingASREngine:
          - Running: \(isRunning)
          - Buffer: \(audioBuffer.count) samples
          - Window: \(windowSize) samples
          - Available windows: \(audioBuffer.count / windowStep)
        """
    }
}
