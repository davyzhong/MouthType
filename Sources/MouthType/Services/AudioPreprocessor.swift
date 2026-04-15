import Foundation
import Accelerate
import os

private let audioPreprocessLog = Logger(subsystem: "com.mouthtype", category: "AudioPreprocess")

/// 音频预处理器
///
/// 提供实时音频增强功能：
/// - 自动增益控制（AGC）
/// - 直流偏移移除
final class AudioPreprocessor: @unchecked Sendable {
    // MARK: - Configuration

    struct Config: Sendable {
        /// 是否启用自动增益控制
        var enableAGC: Bool = true

        /// AGC 目标能量
        var targetEnergy: Float = 0.1

        /// AGC 增益平滑因子
        var agcAlpha: Float = 0.01
    }

    // MARK: - State

    private let config: Config
    private var agcGain: Float = 1.0

    // MARK: - Initialization

    init(config: Config = Config()) {
        self.config = config
        audioPreprocessLog.debug("AudioPreprocessor initialized: AGC=\(config.enableAGC)")
    }

    // MARK: - Public API

    /// 处理音频缓冲
    /// - Parameter samples: 输入 PCM 浮点样本
    /// - Returns: 增强后的样本
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var processed = samples

        // 1. 直流偏移移除
        processed = removeDCOffset(processed)

        // 2. 自动增益控制
        if config.enableAGC {
            processed = applyAGC(processed)
        }

        return processed
    }

    /// 重置处理器状态
    func reset() {
        agcGain = 1.0
        audioPreprocessLog.debug("AudioPreprocessor reset")
    }

    // MARK: - Processing Stages

    private func removeDCOffset(_ samples: [Float]) -> [Float] {
        // 计算均值（DC 偏移）
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))

        // 减去均值（手动实现）
        var result = samples
        for i in 0..<result.count {
            result[i] -= mean
        }

        return result
    }

    private func applyAGC(_ samples: [Float]) -> [Float] {
        // 计算当前能量
        var energy: Float = 0
        vDSP_rmsqv(samples, 1, &energy, vDSP_Length(samples.count))

        guard energy > 0 else { return samples }

        // 计算目标增益
        let targetGain = Float(sqrt(Double(config.targetEnergy) / Double(energy)))

        // 平滑增益变化
        agcGain = agcGain * (1 - config.agcAlpha) + targetGain * config.agcAlpha

        // 限制增益范围（0.5 - 5.0）
        agcGain = max(0.5, min(5.0, agcGain))

        // 应用增益
        var result = samples
        vDSP_vsmul(samples, 1, &agcGain, &result, 1, vDSP_Length(samples.count))

        // 限幅
        for i in 0..<result.count {
            result[i] = max(-1.0, min(1.0, result[i]))
        }

        return result
    }

    // MARK: - Debug Info

    var debugInfo: String {
        let gainStr = String(format: "%.3f", agcGain)
        return "AudioPreprocessor: AGC gain=\(gainStr)"
    }
}
