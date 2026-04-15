import XCTest
@testable import MouthType

// MARK: - TranscriptStabilizer Tests (Refactored)

final class TranscriptStabilizerTests: XCTestCase {
    var stabilizer: TranscriptStabilizer!

    override func setUp() {
        super.setUp()
        stabilizer = TranscriptStabilizer()
    }

    override func tearDown() {
        stabilizer = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        // 默认配置
        let defaultStabilizer = TranscriptStabilizer()
        XCTAssertNotNil(defaultStabilizer.debugInfo)

        // 自定义配置
        let config = TranscriptStabilizer.Config(
            freezeWindowSeconds: 3.0,
            semiStableWindowSeconds: 1.0,
            minCommitLength: 5,
            dedupToleranceSeconds: 0.5
        )
        let customStabilizer = TranscriptStabilizer(config: config)
        XCTAssertNotNil(customStabilizer)
    }

    // MARK: - Append Tests

    func testAppendSegments() {
        // 单个非最终片段
        let segment = createASRSegment(text: "Hello", startTime: 0, endTime: 0.5, isFinal: false)
        let result = stabilizer.append(segment, referenceTime: 1.0)
        XCTAssertNil(result) // 未冻结

        // 多个片段
        stabilizer.reset()
        let segments = [
            createASRSegment(text: "Hello", startTime: 0, endTime: 0.5, isFinal: false),
            createASRSegment(text: "world", startTime: 0.5, endTime: 1.0, isFinal: false),
            createASRSegment(text: "test", startTime: 1.0, endTime: 1.5, isFinal: true)
        ]
        let manyResult = stabilizer.appendMany(segments, referenceTime: 2.0)
        XCTAssertNotNil(manyResult)

        // 最终片段
        stabilizer.reset()
        let finalSegment = createASRSegment(text: "Final result", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(finalSegment, referenceTime: 0.5)
        XCTAssertEqual(stabilizer.getFullText(), "Final result")
    }

    // MARK: - Region Tests

    func testRegionBoundaries() {
        // 冻结区域 - 文本超过冻结窗口
        let frozenSegment = createASRSegment(text: "Old text", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(frozenSegment, referenceTime: 3.0)
        XCTAssertEqual(stabilizer.getFrozenText(), "Old text")

        // 半稳定区域
        stabilizer.reset()
        let oldSegment = createASRSegment(text: "Old", startTime: 0, endTime: 0.5, isFinal: true)
        let recentSegment = createASRSegment(text: "Recent", startTime: 2.0, endTime: 2.5, isFinal: false)
        stabilizer.append(oldSegment, referenceTime: 0.5)
        stabilizer.append(recentSegment, referenceTime: 2.5)
        let stableText = stabilizer.getStableText()
        XCTAssertTrue(stableText.contains("Old"))

        // 活跃区域
        stabilizer.reset()
        let activeSegment = createASRSegment(text: "Active", startTime: 0, endTime: 0.5, isFinal: false)
        stabilizer.append(activeSegment, referenceTime: 0.6)
        XCTAssertEqual(stabilizer.getFullText(), "Active")
    }

    // MARK: - Flush Tests

    func testFlushBehavior() {
        // 刷新未提交文本
        let segment = createASRSegment(text: "Uncommitted", startTime: 0, endTime: 0.5, isFinal: false)
        stabilizer.append(segment, referenceTime: 0.6)
        let flushedText = stabilizer.flush()
        XCTAssertEqual(flushedText, "Uncommitted")

        // 刷新更新冻结计数
        stabilizer.reset()
        let segment1 = createASRSegment(text: "First", startTime: 0, endTime: 0.5, isFinal: false)
        let segment2 = createASRSegment(text: "Second", startTime: 0.5, endTime: 1.0, isFinal: false)
        stabilizer.append(segment1, referenceTime: 0.6)
        stabilizer.append(segment2, referenceTime: 1.1)
        stabilizer.flush()
        let frozenText = stabilizer.getFrozenText()
        XCTAssertTrue(frozenText.contains("First"))
        XCTAssertTrue(frozenText.contains("Second"))

        // 空稳定器刷新
        stabilizer.reset()
        let emptyFlushed = stabilizer.flush()
        XCTAssertEqual(emptyFlushed, "")
    }

    // MARK: - Reset Tests

    func testResetClearsAllState() {
        let segment = createASRSegment(text: "Test", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(segment, referenceTime: 1.0)
        stabilizer.flush()

        stabilizer.reset()

        XCTAssertEqual(stabilizer.getFullText(), "")
        XCTAssertEqual(stabilizer.getFrozenText(), "")
        XCTAssertTrue(stabilizer.debugInfo.contains("Frozen: 0"))
    }

    // MARK: - Get Text Tests

    func testGetTextMethods() {
        // 无冻结文本返回空
        let recentSegment = createASRSegment(text: "Recent", startTime: 0, endTime: 0.5, isFinal: false)
        stabilizer.append(recentSegment, referenceTime: 0.6)
        XCTAssertEqual(stabilizer.getFrozenText(), "")

        // 稳定文本包含冻结和半稳定
        stabilizer.reset()
        let frozenSegment = createASRSegment(text: "Frozen", startTime: 0, endTime: 0.5, isFinal: true)
        let semiStableSegment = createASRSegment(text: "SemiStable", startTime: 1.0, endTime: 1.5, isFinal: false)
        stabilizer.append(frozenSegment, referenceTime: 2.5)
        stabilizer.append(semiStableSegment, referenceTime: 2.0)
        let stableText = stabilizer.getStableText()
        XCTAssertTrue(stableText.contains("Frozen"))

        // 完整文本返回所有片段
        stabilizer.reset()
        let segment1 = createASRSegment(text: "First", startTime: 0, endTime: 0.5, isFinal: false)
        let segment2 = createASRSegment(text: "Second", startTime: 0.5, endTime: 1.0, isFinal: false)
        stabilizer.append(segment1, referenceTime: 0.6)
        stabilizer.append(segment2, referenceTime: 1.1)
        let fullText = stabilizer.getFullText()
        XCTAssertTrue(fullText.contains("First"))
        XCTAssertTrue(fullText.contains("Second"))
    }

    // MARK: - Deduplication Tests

    func testDeduplication() {
        // 空文本视为重复
        XCTAssertTrue(stabilizer.isDuplicate(text: "", currentTime: 0))

        // 相同文本视为重复
        let segment = createASRSegment(text: "Duplicate", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(segment, referenceTime: 3.0)
        XCTAssertTrue(stabilizer.isDuplicate(text: "Duplicate", currentTime: 3.5))

        // 不同文本不视为重复
        stabilizer.reset()
        let originalSegment = createASRSegment(text: "Original", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(originalSegment, referenceTime: 1.0)
        XCTAssertFalse(stabilizer.isDuplicate(text: "Different", currentTime: 1.5))
    }

    // MARK: - Callback Tests

    func testCallbacks() {
        // 冻结文本回调
        var frozenCallbackText: String?
        stabilizer.onFrozenTextAdded = { text in
            frozenCallbackText = text
        }

        let frozenSegment = createASRSegment(text: "Frozen text", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(frozenSegment, referenceTime: 3.0)
        XCTAssertEqual(frozenCallbackText, "Frozen text")

        // 稳定文本更新回调
        var stableCallbackText: String?
        stabilizer.onStableTextUpdated = { text in
            stableCallbackText = text
        }

        stabilizer.reset()
        let stableSegment = createASRSegment(text: "Stable", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(stableSegment, referenceTime: 1.0)
        XCTAssertNotNil(stableCallbackText)

        // 重复文本不触发回调
        stabilizer.reset()
        var callCount = 0
        stabilizer.onFrozenTextAdded = { _ in
            callCount += 1
        }

        let segment1 = createASRSegment(text: "Same", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(segment1, referenceTime: 3.0)
        let segment2 = createASRSegment(text: "Different", startTime: 0.5, endTime: 1.0, isFinal: true)
        stabilizer.append(segment2, referenceTime: 3.5)
        XCTAssertEqual(callCount, 2)
    }

    // MARK: - Debug Info Tests

    func testDebugInfo() {
        // 包含片段计数
        let segment = createASRSegment(text: "Test", startTime: 0, endTime: 0.5, isFinal: false)
        stabilizer.append(segment, referenceTime: 0.6)
        let debugInfo = stabilizer.debugInfo
        XCTAssertTrue(debugInfo.contains("Total segments:"))
        XCTAssertTrue(debugInfo.contains("1"))

        // 包含区域计数
        XCTAssertTrue(debugInfo.contains("Frozen:"))
        XCTAssertTrue(debugInfo.contains("Semi-stable:"))
        XCTAssertTrue(debugInfo.contains("Active:"))

        // 包含冻结文本
        stabilizer.reset()
        let frozenSegment = createASRSegment(text: "Debug test", startTime: 0, endTime: 0.5, isFinal: true)
        stabilizer.append(frozenSegment, referenceTime: 3.0)
        let frozenDebugInfo = stabilizer.debugInfo
        XCTAssertTrue(frozenDebugInfo.contains("Debug test"))
    }

    // MARK: - Integration Tests

    func testMultipleSegmentsIntegration() {
        let segments = [
            createASRSegment(text: "First", startTime: 0, endTime: 0.5, isFinal: true),
            createASRSegment(text: "Second", startTime: 0.5, endTime: 1.0, isFinal: true),
            createASRSegment(text: "Third", startTime: 1.0, endTime: 1.5, isFinal: true)
        ]

        for segment in segments {
            stabilizer.append(segment, referenceTime: 4.0)
        }

        let frozenText = stabilizer.getFrozenText()
        XCTAssertTrue(frozenText.contains("First"))
        XCTAssertTrue(frozenText.contains("Second"))
        XCTAssertTrue(frozenText.contains("Third"))
    }

    func testSegmentsJoinedWithSpaces() {
        let segment1 = createASRSegment(text: "Hello", startTime: 0, endTime: 0.5, isFinal: true)
        let segment2 = createASRSegment(text: "World", startTime: 0.5, endTime: 1.0, isFinal: true)

        stabilizer.append(segment1, referenceTime: 3.0)
        stabilizer.append(segment2, referenceTime: 3.5)

        XCTAssertEqual(stabilizer.getFrozenText(), "Hello World")
    }

    // MARK: - Helper Methods

    private func createASRSegment(text: String, startTime: TimeInterval, endTime: TimeInterval, isFinal: Bool) -> ASRSegment {
        ASRSegment(
            text: text,
            isFinal: isFinal,
            startTime: startTime,
            endTime: endTime
        )
    }
}
