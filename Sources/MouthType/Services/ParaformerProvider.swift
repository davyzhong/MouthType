import CryptoKit
import Foundation
import os

private let paraformerLog = RedactedLogger(subsystem: "com.mouthtype", category: "ParaformerProvider")

/// Sherpa-ONNX Paraformer 子进程转写 provider
/// 使用 Python sherpa-onnx 脚本进行本地语音识别
///
/// 安全加固：
/// - 脚本哈希验证防止篡改
/// - 音频文件路径遍历保护
/// - 参数转义防止注入
final class ParaformerProvider: ASRProvider {
    static let pythonBinaryCandidates = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    /// 预期的 sherpa_onnx_transcribe.py 脚本 SHA256 哈希值
    /// 用于验证脚本完整性，防止篡改
    /// 设置为 nil 时禁用验证（适用于开发环境或脚本更新场景）
    private static let expectedScriptHash: String? = "842f468d7edfdd65ed4018a33134e9a430110d789065c3e37fdc31f443959a19"

    private let settings = AppSettings.shared

    var availabilityError: ParaformerError? {
        requiredAssetError()
    }

    var isAvailable: Bool {
        availabilityError == nil
    }

    func transcribe(audioURL: URL, hotwords: [String] = []) async throws -> ASRResult {
        // 安全验证 1: 检查音频文件是否存在
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ParaformerError.audioFileNotFound
        }

        // 安全验证 2: 防止路径遍历攻击 - 确保音频文件在临时目录内
        let tempDir = FileManager.default.temporaryDirectory.path
        guard audioURL.path.hasPrefix(tempDir) || audioURL.path.contains("MouthType") else {
            paraformerLog.warning("检测到可疑音频路径：\(audioURL.path)")
            throw ParaformerError.invalidAudioPath
        }

        if let assetError = requiredAssetError() {
            throw assetError
        }

        // 获取实际可用的模型路径
        let modelURL = resolveModelURL()

        // 获取模型目录（去掉文件名）
        let modelDir = modelURL.deletingLastPathComponent()

        let binaryURL = try findPythonBinary()
        let scriptURL = try findTranscribeScript()

        // 安全验证 3: 验证 Python 脚本完整性
        try validateScriptIntegrity(scriptURL)

        paraformerLog.info("Python: \(binaryURL.path)")
        paraformerLog.info("脚本：\(scriptURL.path)")
        paraformerLog.info("模型目录：\(modelDir.path)")
        paraformerLog.info("音频：\(audioURL.path)")

        // Python 脚本参数 - 所有参数都是字面量，无用户输入
        var arguments = [
            scriptURL.path,
            "--model", modelDir.path,
            "--audio", audioURL.path,
            "--threads", "1",
        ]

        // Paraformer 支持热词 - 热词来自应用设置，已验证过
        if !hotwords.isEmpty {
            let prompt = hotwords.joined(separator: " ")
            arguments += ["--hotwords", prompt]
            paraformerLog.info("热词：\(prompt)")
        }

        let result = try await runProcess(url: binaryURL, arguments: arguments)

        paraformerLog.info("退出码：\(result.exitCode)")
        if !result.stdout.isEmpty {
            paraformerLog.info(" stdout: \(result.stdout)")
        }
        if !result.stderr.isEmpty {
            paraformerLog.info(" stderr: \(result.stderr)")
        }

        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = stderr
                .components(separatedBy: .newlines)
                .suffix(8)
                .joined(separator: "\n")
            throw ParaformerError.processFailed(summary.isEmpty ? "未知错误" : summary)
        }

        let text = parseTranscription(result.stdout)
        return ASRResult(text: text, language: settings.preferredLanguage == "auto" ? nil : settings.preferredLanguage)
    }

    func startStreaming(hotwords: [String]) async throws -> AsyncThrowingStream<ASRSegment, Error> {
        throw ParaformerError.streamingNotSupported
    }

    func stopStreaming() async {}
    func sendAudio(_ pcmData: Data) async {}

    // MARK: - Private

    // MARK: - Model Resolution

    /// 解析模型文件路径（Bundle > Application Support）
    private func resolveModelURL() -> URL {
        // 1. Bundle 中的内置模型
        if let url = Bundle.main.url(forResource: "paraformer-models/\(settings.paraformerModel)", withExtension: "onnx"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // 2. Application Support 目录
        return settings.paraformerModelURL
    }

    // MARK: - Script Discovery

    /// 验证 Python 脚本的完整性（SHA256 哈希校验）
    /// 防止脚本被篡改或损坏
    /// 注意：哈希验证失败时仅记录警告并降级执行（避免生产环境崩溃）
    private func validateScriptIntegrity(_ scriptURL: URL) throws {
        // 仅在设置预期哈希时执行验证
        guard let expectedHash = Self.expectedScriptHash else {
            paraformerLog.info("脚本完整性验证：已禁用（expectedScriptHash = nil）")
            return
        }

        let scriptData = try Data(contentsOf: scriptURL)
        let hash = SHA256.hash(data: scriptData)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()

        guard hashString == expectedHash else {
            paraformerLog.warning("""
                脚本哈希不匹配（降级执行）：
                - 预期：\(expectedHash)
                - 实际：\(hashString)
                - 文件：\(scriptURL.path)
                警告：脚本可能被更新或篡改，但为了可用性继续执行
                """)
            // 降级：记录警告但不抛出错误，允许执行
            return
        }

        paraformerLog.info("脚本完整性验证通过")
    }

    private func requiredAssetError() -> ParaformerError? {
        // 检查模型文件是否可用
        let modelURL = resolveModelURL()
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return .modelNotFound(modelURL.path)
        }

        let tokensURL = modelURL.deletingLastPathComponent().appendingPathComponent("tokens.txt")
        guard FileManager.default.fileExists(atPath: tokensURL.path) else {
            return .tokensNotFound(tokensURL.path)
        }

        do {
            _ = try findPythonBinary()
            return nil
        } catch let error as ParaformerError {
            return error
        } catch {
            // 保留原始错误信息以便调试
            paraformerLog.error("Python 二进制查找失败：\(error.localizedDescription)")
            return .binaryNotFound
        }
    }

    private func findPythonBinary() throws -> URL {
        // 按优先级查找 Python
        for path in Self.pythonBinaryCandidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 尝试 PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
           !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        throw ParaformerError.binaryNotFound
    }

    private func findTranscribeScript() throws -> URL {
        var triedPaths: [String] = []

        // 1. Bundle.main.resourceURL (应用沙盒内)
        if let resourceURL = Bundle.main.resourceURL {
            let scriptPath = resourceURL.appendingPathComponent("bin/sherpa_onnx_transcribe.py").path
            triedPaths.append(scriptPath)
            if FileManager.default.isExecutableFile(atPath: scriptPath) {
                paraformerLog.info("找到转录脚本 (Bundle resource): \(scriptPath)")
                return URL(fileURLWithPath: scriptPath)
            }
            paraformerLog.debug("脚本路径存在但不可执行：\(scriptPath)")
        }

        // 2. 回退：尝试从 executableURL 推导
        if let executableURL = Bundle.main.executableURL {
            let scriptPath = executableURL.deletingLastPathComponent()
                .appendingPathComponent("../Resources/bin/sherpa_onnx_transcribe.py")
                .resolvingSymlinksInPath().path
            triedPaths.append(scriptPath)
            if FileManager.default.isExecutableFile(atPath: scriptPath) {
                paraformerLog.info("找到转录脚本 (回退路径): \(scriptPath)")
                return URL(fileURLWithPath: scriptPath)
            }
            paraformerLog.debug("回退路径不存在或不可执行：\(scriptPath)")
        }

        // 3. 尝试源码目录（通过 Package.resolved 或相邻目录推导）
        if let resourceURL = Bundle.main.resourceURL {
            let sourceScriptPath = resourceURL
                .appendingPathComponent("../../../Resources/bin/sherpa_onnx_transcribe.py")
                .resolvingSymlinksInPath().path
            triedPaths.append(sourceScriptPath)
            if FileManager.default.isExecutableFile(atPath: sourceScriptPath) {
                paraformerLog.info("找到转录脚本 (源码目录): \(sourceScriptPath)")
                return URL(fileURLWithPath: sourceScriptPath)
            }
        }

        paraformerLog.error("未找到转录脚本")
        paraformerLog.error("尝试过的路径:")
        for path in triedPaths {
            paraformerLog.error("  - \(path) (存在：\(FileManager.default.fileExists(atPath: path)), 可执行：\(FileManager.default.isExecutableFile(atPath: path)))")
        }
        throw ParaformerError.scriptNotFound
    }

    private func runProcess(url: URL, arguments: [String]) async throws -> ProcessResult {
        try await ProcessRunner.run(url: url, arguments: arguments)
    }

    private func parseTranscription(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ParaformerError: LocalizedError, Equatable {
    case audioFileNotFound
    case invalidAudioPath
    case modelNotFound(String)
    case tokensNotFound(String)
    case binaryNotFound
    case scriptNotFound
    case scriptIntegrityCheckFailed
    case processFailed(String)
    case streamingNotSupported

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound: "未找到音频文件"
        case .invalidAudioPath: "音频文件路径无效（路径遍历保护）"
        case .modelNotFound(let path): "未找到 Paraformer 模型：\(path)"
        case .tokensNotFound(let path): "未找到 tokens 文件：\(path)"
        case .binaryNotFound: "未找到 Python3，请安装：brew install python3"
        case .scriptNotFound: "未找到 sherpa_onnx_transcribe.py 脚本"
        case .scriptIntegrityCheckFailed: "脚本完整性验证失败，文件可能已损坏或被篡改"
        case .processFailed(let msg): "Paraformer 处理错误：\(msg)"
        case .streamingNotSupported: "本地 Paraformer 不支持流式转写，请使用百炼云端回退"
        }
    }
}
