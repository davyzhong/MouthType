import Foundation

/// Bailian (Aliyun DashScope) WebSocket streaming ASR provider.
/// Uses Paraformer real-time transcription via WebSocket protocol.
@preconcurrency actor BailianStreamingProvider: ASRProvider {
    private let settings = AppSettings.shared
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var streamContinuation: AsyncThrowingStream<ASRSegment, Error>.Continuation?
    private var isStreaming = false
    private var stopRequested = false
    private var streamGeneration: UInt64 = 0
    private var audioFormat: AudioFormat = .pcm16kMono()
    private let oneShotModel = "qwen3-asr-flash"

    // 重连配置
    private let maxReconnectAttempts = 3
    private let reconnectDelay: TimeInterval = 1.0
    private let reconnectBackoffMultiplier: Double = 2.0

    struct AudioFormat {
        let sampleRate: Int
        let channels: Int
        let bitsPerSample: Int

        static func pcm16kMono() -> AudioFormat {
            AudioFormat(sampleRate: 16000, channels: 1, bitsPerSample: 16)
        }
    }

    nonisolated var isAvailable: Bool {
        let s = AppSettings.shared
        return !s.bailianApiKey.isEmpty && s.bailianWebSocketURL != nil
    }

    func transcribe(audioURL: URL, hotwords: [String]) async throws -> ASRResult {
        guard !settings.bailianApiKey.isEmpty else {
            throw BailianError.apiKeyNotSet
        }
        guard let endpoint = settings.bailianChatCompletionsURL else {
            throw BailianError.invalidHTTPSEndpoint
        }

        let audioData = try Data(contentsOf: audioURL)
        let mimeType = mimeType(for: audioURL)
        let audioBase64 = audioData.base64EncodedString()

        let payload: [String: Any] = [
            "model": oneShotModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": "data:\(mimeType);base64,\(audioBase64)"
                            ]
                        ]
                    ]
                ]
            ],
            "stream": false,
            "asr_options": [
                "enable_itn": false
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(settings.bailianApiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BailianError.connectionFailed
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BailianError.requestFailed(httpResponse.statusCode)
        }

        let text = try extractChatCompletionText(from: data)
        return ASRResult(text: text, language: settings.preferredLanguage == "auto" ? nil : settings.preferredLanguage)
    }

    func startStreaming(hotwords: [String]) async throws -> AsyncThrowingStream<ASRSegment, Error> {
        guard isAvailable else { throw BailianError.apiKeyNotSet }

        streamGeneration &+= 1
        let generation = streamGeneration
        isStreaming = true
        stopRequested = false

        return AsyncThrowingStream { continuation in
            self.streamContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.handleStreamTermination(generation: generation)
                }
            }
            Task {
                await self.runWebSocket(continuation: continuation, hotwords: hotwords, generation: generation)
            }
        }
    }

    func stopStreaming() async {
        guard isStreaming || streamContinuation != nil else { return }
        stopRequested = true
        // Do NOT finish continuation or cancel transport here.
        // runWebSocket will detect stopRequested and drain remaining
        // segments (waiting up to ~2s for a final segment) before
        // finishing the stream itself.
    }

    func sendAudio(_ pcmData: Data) async {
        guard isStreaming, let task = webSocketTask else { return }

        // Wrap PCM data in WebSocket binary frame
        let message = URLSessionWebSocketTask.Message.data(pcmData)
        try? await task.send(message)
    }

    // MARK: - WebSocket

    private func runWebSocket(
        continuation: AsyncThrowingStream<ASRSegment, Error>.Continuation,
        hotwords: [String],
        generation: UInt64
    ) async {
        let apiKey = settings.bailianApiKey
        guard let wsURL = settings.bailianWebSocketURL else {
            await MainActor.run {
                continuation.finish(throwing: BailianError.invalidEndpoint)
            }
            clearStreamingState(generation: generation)
            return
        }

        // 重连循环
        var reconnectAttempt = 0
        var delay = reconnectDelay

        while reconnectAttempt <= maxReconnectAttempts, generation == streamGeneration, isStreaming {
            do {
                try await connectWebSocket(
                    url: wsURL,
                    apiKey: apiKey,
                    continuation: continuation,
                    hotwords: hotwords,
                    generation: generation
                )
                // 如果连接正常退出（stopRequested），则退出重连循环
                if stopRequested { break }
            } catch {
                reconnectAttempt += 1
                if reconnectAttempt > maxReconnectAttempts {
                    await MainActor.run {
                        continuation.finish(throwing: BailianError.connectionFailed)
                    }
                    clearStreamingState(generation: generation)
                    return
                }
                // 指数退避延迟
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                delay *= reconnectBackoffMultiplier
            }
        }

        clearStreamingState(generation: generation)
    }

    /// 建立并运行单个 WebSocket 连接
    private func connectWebSocket(
        url: URL,
        apiKey: String,
        continuation: AsyncThrowingStream<ASRSegment, Error>.Continuation,
        hotwords: [String],
        generation: UInt64
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        guard generation == streamGeneration, isStreaming else {
            task.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw BailianError.connectionFailed
        }

        self.webSocketTask = task
        self.session = session
        task.resume()

        // 发送初始化消息
        let startMsg: [String: Any] = [
            "payload": [
                "format": "pcm",
                "sample_rate": 16000,
                "language": settings.preferredLanguage == "auto" ? "auto" : settings.preferredLanguage,
            ],
            "context": [
                "hotwords": hotwords.joined(separator: " ")
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: startMsg) {
            try? await task.send(.data(data))
        }

        // 接收消息循环
        while generation == streamGeneration, isStreaming, !stopRequested {
            let message = try await task.receive()
            switch message {
            case .string(let text):
                if let segment = parseSegment(from: text) {
                    continuation.yield(segment)
                }
            case .data(let data):
                if let text = String(data: data, encoding: .utf8),
                   let segment = parseSegment(from: text) {
                    continuation.yield(segment)
                }
            @unknown default:
                break
            }
        }

        // 如果 stopRequested，等待最终片段
        if stopRequested {
            try? await drainFinalSegments(task: task, continuation: continuation, generation: generation)
        }

        continuation.finish()
    }

    /// 等待最终片段（stopRequested 后调用）
    private func drainFinalSegments(
        task: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<ASRSegment, Error>.Continuation,
        generation: UInt64
    ) async throws {
        // Give the server up to 2s to send final segments
        let drainTask = Task {
            while generation == streamGeneration {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let segment = parseSegment(from: text) {
                        continuation.yield(segment)
                        if segment.isFinal { return }
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8),
                       let segment = parseSegment(from: text) {
                        continuation.yield(segment)
                        if segment.isFinal { return }
                    }
                @unknown default:
                    return
                }
            }
        }
        // Timeout after 2 seconds
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            drainTask.cancel()
        }
        try? await drainTask.value
        timeout.cancel()
    }

    private func clearStreamingState(generation: UInt64? = nil) {
        guard generation == nil || generation == streamGeneration else { return }
        cancelTransport()
        webSocketTask = nil
        session = nil
        streamContinuation = nil
        isStreaming = false
        stopRequested = false
    }

    private func handleStreamTermination(generation: UInt64) {
        guard generation == streamGeneration else { return }
        cancelTransport()
        clearStreamingState(generation: generation)
    }

    private func cancelTransport() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    private func parseSegment(from json: String) -> ASRSegment? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Bailian returns { payload: { text: "...", is_final: true/false, ... } }
        guard let payload = obj["payload"] as? [String: Any],
              let text = payload["text"] as? String else {
            return nil
        }

        let isFinal = payload["is_final"] as? Bool ?? true
        let startTime = payload["begin_time"] as? TimeInterval ?? 0
        let endTime = payload["end_time"] as? TimeInterval ?? startTime

        return ASRSegment(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            isFinal: isFinal,
            startTime: startTime,
            endTime: endTime
        )
    }
}

private extension BailianStreamingProvider {
    func mimeType(for audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "wav": "audio/wav"
        case "m4a": "audio/m4a"
        case "mp3": "audio/mpeg"
        case "aac": "audio/aac"
        default: "application/octet-stream"
        }
    }

    func extractChatCompletionText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw BailianError.invalidResponse
        }

        if let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let items = message["content"] as? [Any] {
            let text = items.compactMap { item -> String? in
                if let string = item as? String {
                    return string
                }
                if let dict = item as? [String: Any] {
                    if let text = dict["text"] as? String {
                        return text
                    }
                    if let text = dict["content"] as? String {
                        return text
                    }
                }
                return nil
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                return text
            }
        }

        throw BailianError.invalidResponse
    }
}

enum BailianError: LocalizedError {
    case apiKeyNotSet
    case invalidEndpoint
    case invalidHTTPSEndpoint
    case notImplementedForTranscribe
    case connectionFailed
    case requestFailed(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiKeyNotSet: "未配置百炼 API 密钥"
        case .invalidEndpoint: "百炼流式地址必须是 ws:// 或 wss:// 开头的 WebSocket 地址"
        case .invalidHTTPSEndpoint: "百炼非流式地址必须能转换为 https:// chat/completions 地址"
        case .notImplementedForTranscribe: "非流式转写请使用本地 Whisper"
        case .connectionFailed: "连接百炼失败"
        case .requestFailed(let statusCode): "百炼请求失败（\(statusCode)）"
        case .invalidResponse: "百炼返回了无法解析的转写结果"
        }
    }
}
