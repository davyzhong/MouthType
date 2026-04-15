import Foundation

enum NetworkError: LocalizedError {
    case invalidResponse
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "无效的网络响应"
        case .timeout: "请求超时"
        case .cancelled: "请求已取消"
        }
    }
}

final class ModelManager {
    static let shared = ModelManager()

    private let settings = AppSettings.shared

    private init() {}

    // MARK: - Whisper Models

    struct WhisperModel: Identifiable, Hashable {
        let name: String
        let filename: String
        let sizeLabel: String
        let url: URL

        var id: String { filename }
    }

    let availableWhisperModels: [WhisperModel] = [
        WhisperModel(name: "Tiny", filename: "ggml-tiny.bin", sizeLabel: "~75 MB",
                     url: URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!),
        WhisperModel(name: "Base", filename: "ggml-base.bin", sizeLabel: "~142 MB",
                     url: URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!),
        WhisperModel(name: "Small (推荐)", filename: "ggml-small.bin", sizeLabel: "~466 MB",
                     url: URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!),
        WhisperModel(name: "Medium", filename: "ggml-medium.bin", sizeLabel: "~1.5 GB",
                     url: URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!),
        WhisperModel(name: "Large", filename: "ggml-large-v3.bin", sizeLabel: "~3 GB",
                     url: URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!),
    ]

    func whisperModelURL(for model: WhisperModel) -> URL {
        settings.modelsDirectory.appendingPathComponent("whisper/\(model.filename)")
    }

    func isWhisperModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: whisperModelURL(for: model).path)
    }

    // MARK: - Download

    @MainActor
    func download(model: WhisperModel, progress: @escaping (Double) -> Void) async throws {
        let destURL = whisperModelURL(for: model)
        let dir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 如果已存在，先删除
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: model.url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelError.networkError(NetworkError.invalidResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModelError.httpError(httpResponse.statusCode)
        }

        let totalSize = httpResponse.expectedContentLength
        let tempURL = destURL.appendingPathExtension("downloading")
        let fm = FileManager.default

        // 检查磁盘空间
        if totalSize > 0 {
            let availableSpace = try getAvailableDiskSpace()
            let requiredSpace = Int64(Double(totalSize) * 1.5)
            if availableSpace < requiredSpace {
                throw ModelError.insufficientSpace(requiredSpace)
            }
        }

        // 创建临时文件
        fm.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else {
            throw ModelError.downloadFailed
        }

        defer {
            try? handle.close()
        }

        var downloaded: Int64 = 0
        var buffer = Data()
        let chunkSize = 32768

        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    try handle.write(contentsOf: buffer)
                    downloaded += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    if totalSize > 0 {
                        progress(Double(downloaded) / Double(totalSize))
                    }
                }
            }

            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
            }
        } catch {
            throw ModelError.networkError(error)
        }

        try handle.close()
        try fm.moveItem(at: tempURL, to: destURL)
        progress(1.0)
    }

    func deleteWhisperModel(_ model: WhisperModel) throws {
        let url = whisperModelURL(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func getAvailableDiskSpace() throws -> Int64 {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
        return attributes[.systemFreeSize] as? Int64 ?? Int64.max
    }

    // MARK: - Paraformer Models

    struct ParaformerModel: Identifiable, Hashable {
        let name: String
        let filename: String
        let sizeLabel: String
        let url: URL

        var id: String { filename }
    }

    let availableParaformerModels: [ParaformerModel] = [
        ParaformerModel(
            name: "INT8 (中文最佳)",
            filename: "model.int8",
            sizeLabel: "~79 MB",
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-int8-2025-10-07.tar.bz2")!
        ),
    ]

    func paraformerModelURL(for model: ParaformerModel) -> URL {
        settings.modelsDirectory.appendingPathComponent("paraformer/\(model.filename).onnx")
    }

    func isParaformerModelDownloaded(_ model: ParaformerModel) -> Bool {
        let modelURL = paraformerModelURL(for: model)
        let tokensURL = modelURL.deletingLastPathComponent().appendingPathComponent("tokens.txt")
        return FileManager.default.fileExists(atPath: modelURL.path)
            && FileManager.default.fileExists(atPath: tokensURL.path)
    }

    @MainActor
    func download(model: ParaformerModel, progress: @escaping (Double) -> Void) async throws {
        let destURL = paraformerModelURL(for: model)
        let dir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let archiveURL = dir.appendingPathComponent("\(model.filename).tar.bz2")
        let tokensURL = dir.appendingPathComponent("tokens.txt")
        let tempExtractDir = FileManager.default.temporaryDirectory.appendingPathComponent("MouthType-Paraformer-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default

        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        if fm.fileExists(atPath: tokensURL.path) {
            try fm.removeItem(at: tokensURL)
        }
        if fm.fileExists(atPath: archiveURL.path) {
            try fm.removeItem(at: archiveURL)
        }
        if fm.fileExists(atPath: tempExtractDir.path) {
            try fm.removeItem(at: tempExtractDir)
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: model.url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelError.networkError(NetworkError.invalidResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModelError.httpError(httpResponse.statusCode)
        }

        let totalSize = httpResponse.expectedContentLength
        let tempURL = archiveURL.appendingPathExtension("downloading")

        fm.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else {
            throw ModelError.downloadFailed
        }

        defer {
            try? handle.close()
            try? fm.removeItem(at: tempURL)
            try? fm.removeItem(at: archiveURL)
            try? fm.removeItem(at: tempExtractDir)
        }

        var downloaded: Int64 = 0
        var buffer = Data()
        let chunkSize = 32768

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if totalSize > 0 {
                    progress(Double(downloaded) / Double(totalSize) * 0.9)
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        try handle.close()
        try fm.moveItem(at: tempURL, to: archiveURL)

        try fm.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archiveURL.path, "-C", tempExtractDir.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ModelError.extractFailed
        }

        let extractedDir = tempExtractDir.appendingPathComponent("sherpa-onnx-paraformer-zh-int8-2025-10-07", isDirectory: true)
        let extractedModelURL = extractedDir.appendingPathComponent("model.int8.onnx")
        let extractedTokensURL = extractedDir.appendingPathComponent("tokens.txt")
        guard fm.fileExists(atPath: extractedModelURL.path),
              fm.fileExists(atPath: extractedTokensURL.path) else {
            throw ModelError.extractFailed
        }

        try fm.copyItem(at: extractedModelURL, to: destURL)
        try fm.copyItem(at: extractedTokensURL, to: tokensURL)
        progress(1.0)
    }

    func deleteParaformerModel(_ model: ParaformerModel) throws {
        let url = paraformerModelURL(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum ModelError: LocalizedError {
    case networkError(Error)
    case httpError(Int)
    case downloadFailed
    case extractFailed
    case modelNotFound
    case insufficientSpace(Int64)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .networkError(let error): "网络错误：\(error.localizedDescription)"
        case .httpError(let code): "HTTP 错误：状态码 \(code)"
        case .downloadFailed: "模型下载失败，请检查网络连接"
        case .extractFailed: "模型解压失败"
        case .modelNotFound: "模型文件未找到"
        case .insufficientSpace(let needed): "磁盘空间不足，需要 \(needed / 1024 / 1024) MB"
        case .checksumMismatch: "模型校验和不匹配，文件可能已损坏"
        }
    }

    /// 获取用于显示的简短错误消息
    var shortMessage: String {
        switch self {
        case .networkError: "网络错误"
        case .httpError(let code): "HTTP \(code)"
        case .downloadFailed: "下载失败"
        case .extractFailed: "解压失败"
        case .modelNotFound: "模型未找到"
        case .insufficientSpace: "空间不足"
        case .checksumMismatch: "校验失败"
        }
    }
}

extension ModelError: Equatable {
    static func == (lhs: ModelError, rhs: ModelError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError, .networkError): return true
        case (.httpError(let a), .httpError(let b)): return a == b
        case (.downloadFailed, .downloadFailed): return true
        case (.extractFailed, .extractFailed): return true
        case (.modelNotFound, .modelNotFound): return true
        case (.insufficientSpace(let a), .insufficientSpace(let b)): return a == b
        case (.checksumMismatch, .checksumMismatch): return true
        default: return false
        }
    }
}
