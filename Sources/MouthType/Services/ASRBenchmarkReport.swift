import Foundation

/// ASR 基准测试报告
///
/// 生成可基准测试的 ASR 质量报告
struct ASRBenchmarkReport {
    let reportDate: Date
    let totalCases: Int
    let passedCases: Int
    let failedCases: Int
    let skippedCases: Int
    let caseResults: [ASRCaseResult]
    let summary: BenchmarkSummary

    struct ASRCaseResult: Codable {
        let caseId: String
        let name: String
        let status: TestStatus
        let latencyMs: Double?
        let wordErrorRate: Double?
        let insertionOutcome: String?
        let skipReason: String?
        let errorMessage: String?

        enum TestStatus: String, Codable {
            case passed
            case failed
            case skipped
        }
    }

    struct BenchmarkSummary: Codable {
        let totalDuration: TimeInterval
        let averageLatencyMs: Double
        let p50LatencyMs: Double
        let p95LatencyMs: Double
        let p99LatencyMs: Double
        let insertionSuccessRate: Double
        let averageWER: Double
        let skippedReasons: [String: Int]
    }

    /// 从回放结果创建报告
    static func create(from replayResults: [String: Any]) -> ASRBenchmarkReport {
        let caseResults: [ASRCaseResult] = []
        let summary = BenchmarkSummary(
            totalDuration: 0,
            averageLatencyMs: 0,
            p50LatencyMs: 0,
            p95LatencyMs: 0,
            p99LatencyMs: 0,
            insertionSuccessRate: 0,
            averageWER: 0,
            skippedReasons: [:]
        )

        // TODO: 解析回放结果
        return ASRBenchmarkReport(
            reportDate: Date(),
            totalCases: caseResults.count,
            passedCases: caseResults.filter { $0.status == .passed }.count,
            failedCases: caseResults.filter { $0.status == .failed }.count,
            skippedCases: caseResults.filter { $0.status == .skipped }.count,
            caseResults: caseResults,
            summary: summary
        )
    }

    /// 生成 JSON 报告
    func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let container = ReportContainer(
            metadata: Metadata(
                reportVersion: "1.0",
                generatedAt: ISO8601DateFormatter().string(from: reportDate),
                toolVersion: "MouthType Phase 7"
            ),
            summary: summary,
            results: caseResults
        )

        return try encoder.encode(container)
    }

    /// 生成人类可读的摘要
    func humanReadableSummary() -> String {
        var output: [String] = []

        output.append("=== ASR 基准测试报告 ===")
        output.append("生成时间：\(ISO8601DateFormatter().string(from: reportDate))")
        output.append("")
        output.append("用例统计:")
        output.append("  总计：\(totalCases)")
        output.append("  通过：\(passedCases)")
        output.append("  失败：\(failedCases)")
        output.append("  跳过：\(skippedCases)")
        output.append("")
        output.append("延迟指标:")
        output.append("  平均延迟：\(String(format: "%.2f", summary.averageLatencyMs)) ms")
        output.append("  P50 延迟：\(String(format: "%.2f", summary.p50LatencyMs)) ms")
        output.append("  P95 延迟：\(String(format: "%.2f", summary.p95LatencyMs)) ms")
        output.append("  P99 延迟：\(String(format: "%.2f", summary.p99LatencyMs)) ms")
        output.append("")
        output.append("插入成功率：\(String(format: "%.1f", summary.insertionSuccessRate * 100))%")
        output.append("平均词错误率 (WER): \(String(format: "%.2f", summary.averageWER))")

        if !summary.skippedReasons.isEmpty {
            output.append("")
            output.append("跳过原因分布:")
            for (reason, count) in summary.skippedReasons {
                output.append("  - \(reason): \(count)")
            }
        }

        return output.joined(separator: "\n")
    }

    private struct ReportContainer: Codable {
        let metadata: Metadata
        let summary: BenchmarkSummary
        let results: [ASRCaseResult]
    }

    private struct Metadata: Codable {
        let reportVersion: String
        let generatedAt: String
        let toolVersion: String
    }
}

/// ASR 基准测试验证器
struct ASRBenchmarkVerifier {
    let config: VerifierConfig

    struct VerifierConfig {
        let maxP95LatencyMs: Double
        let minInsertionSuccessRate: Double
        let maxAverageWER: Double
        let maxSkipRate: Double
    }

    /// 默认配置
    static let defaultConfig = VerifierConfig(
        maxP95LatencyMs: 500,
        minInsertionSuccessRate: 0.95,
        maxAverageWER: 0.10,
        maxSkipRate: 0.20
    )

    /// 验证报告
    func verify(report: ASRBenchmarkReport) -> VerificationResult {
        var issues: [VerificationIssue] = []

        // 检查 P95 延迟
        if report.summary.p95LatencyMs > config.maxP95LatencyMs {
            issues.append(.p95LatencyExceeded(
                expected: config.maxP95LatencyMs,
                actual: report.summary.p95LatencyMs
            ))
        }

        // 检查插入成功率
        if report.summary.insertionSuccessRate < config.minInsertionSuccessRate {
            issues.append(.insertionSuccessRateTooLow(
                expected: config.minInsertionSuccessRate,
                actual: report.summary.insertionSuccessRate
            ))
        }

        // 检查词错误率
        if report.summary.averageWER > config.maxAverageWER {
            issues.append(.wordErrorRateTooHigh(
                expected: config.maxAverageWER,
                actual: report.summary.averageWER
            ))
        }

        // 检查跳过率
        let skipRate = Double(report.skippedCases) / Double(report.totalCases)
        if skipRate > config.maxSkipRate {
            issues.append(.skipRateTooHigh(
                expected: config.maxSkipRate,
                actual: skipRate
            ))
        }

        return VerificationResult(
            passed: issues.isEmpty,
            issues: issues,
            reportDate: report.reportDate
        )
    }

    enum VerificationIssue: CustomStringConvertible {
        case p95LatencyExceeded(expected: Double, actual: Double)
        case insertionSuccessRateTooLow(expected: Double, actual: Double)
        case wordErrorRateTooHigh(expected: Double, actual: Double)
        case skipRateTooHigh(expected: Double, actual: Double)

        var description: String {
            switch self {
            case .p95LatencyExceeded(let expected, let actual):
                return "P95 延迟超标：期望 <= \(expected)ms, 实际 \(actual)ms"
            case .insertionSuccessRateTooLow(let expected, let actual):
                return "插入成功率过低：期望 >= \(expected * 100)%, 实际 \(actual * 100)%"
            case .wordErrorRateTooHigh(let expected, let actual):
                return "词错误率过高：期望 <= \(expected * 100)%, 实际 \(actual * 100)%"
            case .skipRateTooHigh(let expected, let actual):
                return "跳过率过高：期望 <= \(expected * 100)%, 实际 \(actual * 100)%"
            }
        }
    }

    struct VerificationResult {
        let passed: Bool
        let issues: [VerificationIssue]
        let reportDate: Date

        var summary: String {
            if passed {
                return "✅ 验证通过 (\(ISO8601DateFormatter().string(from: reportDate)))"
            } else {
                let issueDescriptions = issues.map { $0.description }.joined(separator: "\n")
                return "❌ 验证失败:\n\(issueDescriptions)"
            }
        }
    }
}
