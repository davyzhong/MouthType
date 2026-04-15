import XCTest
@testable import MouthType

// MARK: - ASRBenchmarkReport Tests (Refactored)

final class ASRBenchmarkReportTests: XCTestCase {

    // MARK: - Initialization Tests

    func testCreateEmptyReport() {
        let report = ASRBenchmarkReport.create(from: [:])

        XCTAssertEqual(report.totalCases, 0)
        XCTAssertEqual(report.passedCases, 0)
        XCTAssertEqual(report.failedCases, 0)
        XCTAssertEqual(report.skippedCases, 0)
        XCTAssertNotNil(report.summary)
        XCTAssertNotNil(report.reportDate)
    }

    // MARK: - Summary Tests

    func testSummaryDefaultValues() {
        let report = ASRBenchmarkReport.create(from: [:])
        let summary = report.summary

        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertEqual(summary.averageLatencyMs, 0)
        XCTAssertEqual(summary.p50LatencyMs, 0)
        XCTAssertEqual(summary.p95LatencyMs, 0)
        XCTAssertEqual(summary.p99LatencyMs, 0)
        XCTAssertEqual(summary.insertionSuccessRate, 0)
        XCTAssertEqual(summary.averageWER, 0)
        XCTAssertTrue(summary.skippedReasons.isEmpty)
    }

    // MARK: - JSON Serialization Tests

    func testJSONSerialization() {
        let report = ASRBenchmarkReport.create(from: [:])

        // 序列化为 JSON
        let jsonData = try? report.toJSON()
        XCTAssertNotNil(jsonData)
        XCTAssertTrue(jsonData!.count > 0)

        // 反序列化验证
        let json = try? JSONSerialization.jsonObject(with: jsonData!, options: []) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["summary"])
        XCTAssertNotNil(json?["metadata"])
        XCTAssertNotNil(json?["results"])

        // 验证元数据
        let metadata = json?["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["reportVersion"] as? String, "1.0")
        XCTAssertNotNil(metadata?["generatedAt"])
        XCTAssertEqual(metadata?["toolVersion"] as? String, "MouthType Phase 7")
    }

    // MARK: - Human Readable Summary Tests

    func testHumanReadableSummary() {
        let report = ASRBenchmarkReport.create(from: [:])
        let summary = report.humanReadableSummary()

        // 验证包含所有必要的信息
        let expectedKeywords = [
            "ASR 基准测试报告",
            "总计", "通过", "失败", "跳过",
            "平均延迟", "P50 延迟", "P95 延迟", "P99 延迟",
            "插入成功率",
            "WER"
        ]

        for keyword in expectedKeywords {
            XCTAssertTrue(
                summary.contains(keyword),
                "人类可读摘要应包含 '\(keyword)'"
            )
        }
    }

    // MARK: - Verifier Tests

    func testVerifierDefaultConfig() {
        let config = ASRBenchmarkVerifier.defaultConfig

        XCTAssertEqual(config.maxP95LatencyMs, 500)
        XCTAssertEqual(config.minInsertionSuccessRate, 0.95)
        XCTAssertEqual(config.maxAverageWER, 0.10)
        XCTAssertEqual(config.maxSkipRate, 0.20)
    }

    func testVerifierWithValidReport() {
        let config = ASRBenchmarkVerifier.defaultConfig
        let verifier = ASRBenchmarkVerifier(config: config)
        let report = createReport(
            totalCases: 100,
            passedCases: 95,
            failedCases: 0,
            skippedCases: 5,
            p95LatencyMs: 300,
            insertionSuccessRate: 0.98,
            averageWER: 0.05
        )

        let result = verifier.verify(report: report)

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testVerifierFailsWithInvalidMetrics() {
        let config = ASRBenchmarkVerifier.defaultConfig
        let verifier = ASRBenchmarkVerifier(config: config)

        let testCases: [(String, Int, Int, Double, Double, Double, ASRBenchmarkVerifier.VerificationIssue)] = [
            ("高延迟", 95, 0, 600, 0.98, 0.05, .p95LatencyExceeded(expected: 500, actual: 600)),
            ("低插入率", 85, 5, 300, 0.85, 0.05, .insertionSuccessRateTooLow(expected: 0.95, actual: 0.85)),
            ("高 WER", 95, 0, 300, 0.98, 0.15, .wordErrorRateTooHigh(expected: 0.10, actual: 0.15)),
        ]

        for (name, passedCases, failedCases, p95Latency, insertionRate, wer, expectedIssue) in testCases {
            let report = createReport(
                totalCases: 100,
                passedCases: passedCases,
                failedCases: failedCases,
                skippedCases: 5,
                p95LatencyMs: p95Latency,
                insertionSuccessRate: insertionRate,
                averageWER: wer
            )

            let result = verifier.verify(report: report)

            XCTAssertFalse(result.passed, "\(name) 应验证失败")
            XCTAssertTrue(result.issues.contains { issue in
                type(of: issue) == type(of: expectedIssue)
            }, "\(name) 应包含正确的错误类型")
        }

        // 高跳过率单独测试
        let skipReport = createReport(
            totalCases: 100,
            passedCases: 70,
            failedCases: 0,
            skippedCases: 30,
            p95LatencyMs: 300,
            insertionSuccessRate: 0.98,
            averageWER: 0.05
        )
        let skipResult = verifier.verify(report: skipReport)
        XCTAssertFalse(skipResult.passed, "高跳过率应验证失败")
        XCTAssertTrue(skipResult.issues.contains { issue in
            if case .skipRateTooHigh = issue { return true }
            return false
        }, "高跳过率应包含跳过率错误")
    }

    func testVerifierMultipleIssues() {
        let config = ASRBenchmarkVerifier.defaultConfig
        let verifier = ASRBenchmarkVerifier(config: config)

        let report = createReport(
            totalCases: 100,
            passedCases: 60,
            failedCases: 10,
            skippedCases: 30,
            p95LatencyMs: 700,     // 高延迟
            insertionSuccessRate: 0.70,  // 低插入率
            averageWER: 0.20       // 高 WER
        )

        let result = verifier.verify(report: report)

        XCTAssertFalse(result.passed)
        XCTAssertGreaterThan(result.issues.count, 1)
    }

    // MARK: - Verification Issue Tests

    func testVerificationIssueDescriptions() {
        let issues: [(ASRBenchmarkVerifier.VerificationIssue, [String])] = [
            (.p95LatencyExceeded(expected: 500, actual: 600), ["P95", "延迟", "500", "600"]),
            (.insertionSuccessRateTooLow(expected: 0.95, actual: 0.80), ["插入成功率", "95", "80"]),
            (.wordErrorRateTooHigh(expected: 0.10, actual: 0.15), ["词错误率", "10", "15"]),
            (.skipRateTooHigh(expected: 0.20, actual: 0.30), ["跳过率", "20", "30"]),
        ]

        for (issue, expectedKeywords) in issues {
            let description = issue.description
            for keyword in expectedKeywords {
                XCTAssertTrue(
                    description.contains(keyword),
                    "错误描述应包含 '\(keyword)'"
                )
            }
        }
    }

    // MARK: - Verification Result Tests

    func testVerificationResultSummaries() {
        // 通过结果
        let passResult = ASRBenchmarkVerifier.VerificationResult(
            passed: true,
            issues: [],
            reportDate: Date()
        )
        let passSummary = passResult.summary
        XCTAssertTrue(passSummary.contains("✅"))
        XCTAssertTrue(passSummary.contains("验证通过"))

        // 失败结果
        let failResult = ASRBenchmarkVerifier.VerificationResult(
            passed: false,
            issues: [.p95LatencyExceeded(expected: 500, actual: 600)],
            reportDate: Date()
        )
        let failSummary = failResult.summary
        XCTAssertTrue(failSummary.contains("❌"))
        XCTAssertTrue(failSummary.contains("验证失败"))
    }

    // MARK: - Helper Methods

    private func createReport(
        totalCases: Int,
        passedCases: Int,
        failedCases: Int,
        skippedCases: Int,
        p95LatencyMs: Double,
        insertionSuccessRate: Double,
        averageWER: Double
    ) -> ASRBenchmarkReport {
        ASRBenchmarkReport(
            reportDate: Date(),
            totalCases: totalCases,
            passedCases: passedCases,
            failedCases: failedCases,
            skippedCases: skippedCases,
            caseResults: [],
            summary: ASRBenchmarkReport.BenchmarkSummary(
                totalDuration: TimeInterval(totalCases) * 0.1,
                averageLatencyMs: p95LatencyMs * 0.5,
                p50LatencyMs: p95LatencyMs * 0.3,
                p95LatencyMs: p95LatencyMs,
                p99LatencyMs: p95LatencyMs * 1.2,
                insertionSuccessRate: insertionSuccessRate,
                averageWER: averageWER,
                skippedReasons: ["fixture_not_found": skippedCases]
            )
        )
    }
}
