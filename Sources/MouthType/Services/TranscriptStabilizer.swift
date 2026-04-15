import Foundation
import os

private let stabilizerLog = Logger(subsystem: "com.mouthtype", category: "TranscriptStabilizer")

/// 增量转写稳定器 - 管理流式 ASR 的部分结果，防止文本抖动
///
/// 将转写文本分为三个区域：
/// - **冻结区域** - 已确认的最终文本，不再修改
/// - **半稳定区域** - 较早期的部分结果，相对稳定但可能微调
/// - **活跃区域** - 最新的转写结果，可能频繁变化
///
/// Thread safety: Designed for MainActor usage (called from UI/async contexts)
final class TranscriptStabilizer: @unchecked Sendable {
    // MARK: - Configuration

    struct Config: Sendable {
        /// 冻结窗口时长（秒）- 超过此时长的文本冻结
        var freezeWindowSeconds: TimeInterval = 2.0

        /// 半稳定窗口时长（秒）- 超过此时长的文本进入半稳定
        var semiStableWindowSeconds: TimeInterval = 0.8

        /// 最小提交文本长度（字符）- 少于这个长度的结果不单独提交
        var minCommitLength: Int = 3

        /// 去重时间容差（秒）- 在此时间内的相同文本视为重复
        var dedupToleranceSeconds: TimeInterval = 0.3
    }

    // MARK: - Segment Types

    /// 转写片段，带时间戳和稳定状态
    struct TranscriptSegment: Sendable {
        let id: String
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let isFinal: Bool

        init(id: String = UUID().uuidString, text: String, startTime: TimeInterval, endTime: TimeInterval, isFinal: Bool) {
            self.id = id
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
            self.isFinal = isFinal
        }
    }

    /// 区域类型
    enum RegionType: Sendable {
        case frozen          // 冻结区域 - 已最终确认
        case semiStable      // 半稳定区域 - 相对稳定
        case active          // 活跃区域 - 可能频繁变化
    }

    // MARK: - State

    private var segments: [TranscriptSegment] = []
    private var frozenCount: Int = 0
    private var lastCommitTime: Date?
    private var lastFinalText: String = ""
    private let config: Config

    // MARK: - Callbacks

    /// 当冻结区域增长时调用（有新的最终文本）
    var onFrozenTextAdded: (@Sendable (String) -> Void)?

    /// 当稳定文本更新时调用（用于 UI 实时预览）
    var onStableTextUpdated: (@Sendable (String) -> Void)?

    // MARK: - Initialization

    init(config: Config = Config()) {
        self.config = config
        stabilizerLog.debug("TranscriptStabilizer initialized: freezeWindow=\(config.freezeWindowSeconds)s, semiStableWindow=\(config.semiStableWindowSeconds)s")
    }

    // MARK: - Public API

    /// 接收新的转写片段
    /// - Parameters:
    ///   - segment: ASR 片段
    ///   - referenceTime: 参考时间（用于计算区域）
    /// - Returns: 如果冻结区域有增长，返回新增的冻结文本
    @discardableResult
    func append(_ segment: ASRSegment, referenceTime: TimeInterval? = nil) -> String? {
        // 使用简体中文文本
        let transcriptSegment = TranscriptSegment(
            text: segment.simplifiedText,
            startTime: segment.startTime,
            endTime: segment.endTime,
            isFinal: segment.isFinal
        )

        segments.append(transcriptSegment)
        stabilizerLog.trace("Appended segment: \(segment.text) (final=\(segment.isFinal))")

        // 计算区域并获取冻结文本
        let frozenText = computeRegions(referenceTime: referenceTime ?? segment.endTime)

        // 检查是否有新的冻结文本
        if frozenText != lastFinalText {
            let newText = frozenText.dropFirst(lastFinalText.count)
            if !newText.isEmpty {
                lastFinalText = frozenText
                onFrozenTextAdded?(String(newText))
                return String(newText)
            }
            lastFinalText = frozenText
        }

        // 通知稳定文本更新
        onStableTextUpdated?(frozenText)

        return nil
    }

    /// 批量接收片段（用于回放或批处理）
    /// - Parameters:
    ///   - segments: ASR 片段数组
    ///   - referenceTime: 参考时间
    /// - Returns: 累计的冻结文本
    func appendMany(_ segments: [ASRSegment], referenceTime: TimeInterval? = nil) -> String {
        var result: String = ""
        for segment in segments {
            if let newText = append(segment, referenceTime: referenceTime) {
                result += newText
            }
        }
        return result
    }

    /// 获取当前冻结区域文本
    /// - Returns: 已最终确认的文本
    func getFrozenText() -> String {
        guard frozenCount > 0 else { return "" }
        return segments.prefix(frozenCount).map { $0.text }.joined(separator: " ")
    }

    /// 获取当前稳定文本（冻结 + 半稳定）
    /// - Returns: 稳定文本（适合显示给用户）
    func getStableText() -> String {
        let stableEndIndex = findSemiStableBoundary()
        guard stableEndIndex > 0 else { return "" }
        return segments.prefix(stableEndIndex).map { $0.text }.joined(separator: " ")
    }

    /// 获取完整文本（所有区域）
    /// - Returns: 所有片段拼接的文本
    func getFullText() -> String {
        segments.map { $0.text }.joined(separator: " ")
    }

    /// 强制提交当前活跃区域
    /// 用于会话结束时将剩余文本提交
    /// - Returns: 提交的文本
    @discardableResult
    func flush() -> String {
        let remainingText = getFullText().dropFirst(getFrozenText().count)
        frozenCount = segments.count
        lastFinalText = getFullText()

        if !remainingText.isEmpty {
            stabilizerLog.info("Flushed remaining text: \(remainingText.count) chars")
            onFrozenTextAdded?(String(remainingText))
        }

        return String(remainingText)
    }

    /// 重置稳定器状态
    func reset() {
        segments.removeAll()
        frozenCount = 0
        lastCommitTime = nil
        lastFinalText = ""
        stabilizerLog.debug("TranscriptStabilizer reset")
    }

    // MARK: - Region Computation

    /// 计算各区域边界
    /// - Returns: (冻结边界，半稳定边界)
    private func computeRegions(referenceTime: TimeInterval) -> String {
        guard !segments.isEmpty else { return "" }

        // 找到冻结区域边界 - 超过 freezeWindow 的片段
        let freezeThreshold = referenceTime - config.freezeWindowSeconds
        let newFrozenCount = segments.firstIndex { $0.endTime > freezeThreshold } ?? segments.count

        // 更新冻结计数
        if newFrozenCount > frozenCount {
            let newlyFrozen = segments[frozenCount..<newFrozenCount]
            stabilizerLog.debug("Promoted \(newlyFrozen.count) segments to frozen")
            frozenCount = newFrozenCount
        }

        // 返回冻结文本
        return segments.prefix(frozenCount).map { $0.text }.joined(separator: " ")
    }

    /// 找到半稳定区域边界
    /// - Returns: 半稳定区域的结束索引
    private func findSemiStableBoundary() -> Int {
        guard !segments.isEmpty, let lastTime = segments.last?.endTime else {
            return frozenCount
        }

        let semiStableThreshold = lastTime - config.semiStableWindowSeconds
        let boundary = segments.firstIndex { $0.endTime > semiStableThreshold } ?? segments.count

        return max(frozenCount, boundary)
    }

    // MARK: - Deduplication

    /// 检查文本是否为重复
    /// - Parameters:
    ///   - text: 待检查文本
    ///   - currentTime: 当前时间
    /// - Returns: 是否为重复
    func isDuplicate(text: String, currentTime: TimeInterval) -> Bool {
        guard !text.isEmpty else { return true }

        // 检查与最后确认文本是否相同
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == lastFinalText.trimmingCharacters(in: .whitespacesAndNewlines) {
            return true
        }

        // 检查时间容差内的重复
        if let lastCommit = lastCommitTime,
           Date().timeIntervalSince(lastCommit) < config.dedupToleranceSeconds {
            // 短时间内相同文本视为重复
            return false // 允许通过，由调用方决定是否跳过
        }

        return false
    }

    // MARK: - Debug Info

    /// 当前状态信息
    var debugInfo: String {
        let semiStableEnd = findSemiStableBoundary()
        return """
        TranscriptStabilizer:
          - Total segments: \(segments.count)
          - Frozen: \(frozenCount) segments
          - Semi-stable: \(semiStableEnd - frozenCount) segments
          - Active: \(segments.count - semiStableEnd) segments
          - Frozen text: "\(getFrozenText())"
        """
    }
}
