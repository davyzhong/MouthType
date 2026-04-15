import CryptoKit
import Foundation
import os

private let whisperLog = RedactedLogger(subsystem: "com.mouthtype", category: "WhisperProvider")

final class WhisperProvider: ASRProvider {
    private let settings = AppSettings.shared

    /// whisper-cli 二进制文件的预期 SHA256 哈希值（可选）
    /// 如果设置，将验证二进制文件完整性
    /// 注意：Homebrew 安装的版本可能不同，此验证仅适用于 bundled 二进制
    // private static let expectedBinaryHash = "..."

    var availabilityError: WhisperError? {
        let modelURL = settings.whisperModelURL
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return .modelNotFound(modelURL.path)
        }

        do {
            _ = try findWhisperBinary()
            return nil
        } catch let error as WhisperError {
            return error
        } catch {
            return .binaryNotFound
        }
    }

    var isAvailable: Bool {
        availabilityError == nil
    }

    /// Transcribe audio file using whisper.cpp CLI subprocess
    func transcribe(audioURL: URL, hotwords: [String] = []) async throws -> ASRResult {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WhisperError.audioFileNotFound
        }

        let modelURL = settings.whisperModelURL
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperError.modelNotFound(modelURL.path)
        }

        let binaryURL = try findWhisperBinary()

        var arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "--output-txt",
            "-nt",
        ]

        let language = settings.preferredLanguage
        if language != "auto" {
            arguments += ["-l", language]
        }

        if !hotwords.isEmpty {
            let prompt = hotwords.joined(separator: " ")
            arguments += ["--prompt", prompt]
        }

        let result = try await runProcess(url: binaryURL, arguments: arguments)

        if result.exitCode != 0 {
            throw WhisperError.processFailed(result.stderr)
        }

        let text = parseTranscription(result.stdout)
        return ASRResult(text: text, language: settings.preferredLanguage == "auto" ? nil : settings.preferredLanguage)
    }

    func startStreaming(hotwords: [String]) async throws -> AsyncThrowingStream<ASRSegment, Error> {
        throw WhisperError.streamingNotSupported
    }

    func stopStreaming() async {}

    func sendAudio(_ pcmData: Data) async {}

    // MARK: - Private

    private func findWhisperBinary() throws -> URL {
        let candidates = [
            // brew install whisper-cpp → /opt/homebrew/bin/whisper-cli
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            // Bundled binary (future)
            Bundle.main.resourceURL?.appendingPathComponent("bin/whisper-cli").path,
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("whisper-cli").path,
            // Legacy names
            "/opt/homebrew/bin/whisper-cpp-cli",
            "/usr/local/bin/whisper-cpp-cli",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                let url = URL(fileURLWithPath: path)

                // 如果是 Bundled 二进制文件，验证完整性
                if path.contains(Bundle.main.resourcePath ?? "") {
                    try validateBinaryIntegrity(at: url)
                }

                return url
            }
        }

        throw WhisperError.binaryNotFound
    }

    /// 验证二进制文件完整性（SHA256 哈希校验）
    private func validateBinaryIntegrity(at url: URL) throws {
        // 仅在设置预期哈希时执行验证
        guard let expectedHash = settings.expectedWhisperBinaryHash else {
            return
        }

        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()

        guard hashString == expectedHash else {
            whisperLog.warning("二进制文件哈希不匹配：\(url.path)")
            throw WhisperError.binaryIntegrityCheckFailed
        }

        whisperLog.info("二进制文件完整性验证通过")
    }

    private func runProcess(url: URL, arguments: [String]) async throws -> ProcessResult {
        try await ProcessRunner.run(url: url, arguments: arguments)
    }

    private func parseTranscription(_ output: String) -> String {
        let lines = output.components(separatedBy: "\n")

        // whisper.cpp --output-txt prints plain text transcription
        // Filter out whisper log lines
        let textLines = lines.filter { line in
            !line.hasPrefix("[") && !line.isEmpty && !line.contains("whisper_") && !line.contains("system_info")
        }

        return textLines
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperError: LocalizedError {
    case audioFileNotFound
    case modelNotFound(String)
    case binaryNotFound
    case processFailed(String)
    case streamingNotSupported
    case binaryIntegrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound: "未找到音频文件"
        case .modelNotFound(let path): "未找到 Whisper 模型：\(path)"
        case .binaryNotFound: "未找到 whisper-cli 可执行文件，请先执行：brew install whisper-cpp"
        case .processFailed(let msg): "Whisper 进程执行失败：\(msg)"
        case .streamingNotSupported: "本地 Whisper 不支持流式转写，请使用百炼云端回退"
        case .binaryIntegrityCheckFailed: "Whisper 二进制文件校验失败，文件可能已损坏或被篡改"
        }
    }
}
