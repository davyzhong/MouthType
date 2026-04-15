import AVFoundation
import Foundation
import os

private let audioCaptureLog = Logger(subsystem: "com.mouthtype", category: "AudioCapture")

// MARK: - Audio Configuration

/// 音频配置常量
enum AudioConfiguration {
    /// ASR 引擎目标采样率：16kHz
    static let targetSampleRate: Double = 16000
    /// Tap 停止宽限期：基于音频缓冲排空时间
    static let tapStopGracePeriod: TimeInterval = 0.08
    /// 捕获按键释放后的尾音延迟
    static let tailAudioCaptureDelay: TimeInterval = 0.15
    /// 音频通道数：单声道
    static let channels: AVAudioChannelCount = 1
    /// 每样本位数：16-bit PCM
    static let bitsPerSample: UInt16 = 16
}

final class AudioCapture: @unchecked Sendable {
    final class TapDrainCoordinator {
        private let condition = NSCondition()
        private var isAcceptingCallbacks = false
        private var activeCallbacks = 0
        private var stopAcceptanceDeadline: Date?

        func startSession() {
            condition.lock()
            isAcceptingCallbacks = true
            activeCallbacks = 0
            stopAcceptanceDeadline = nil
            condition.unlock()
        }

        func beginCallback() -> Bool {
            condition.lock()
            defer { condition.unlock() }

            if isAcceptingCallbacks {
                activeCallbacks += 1
                return true
            }

            if let deadline = stopAcceptanceDeadline, Date() < deadline {
                activeCallbacks += 1
                return true
            }

            return false
        }

        func endCallback() {
            condition.lock()
            activeCallbacks -= 1
            if activeCallbacks == 0 {
                condition.broadcast()
            }
            condition.unlock()
        }

        func beginStopping(gracePeriod: TimeInterval = 0) {
            condition.lock()
            isAcceptingCallbacks = false
            stopAcceptanceDeadline = gracePeriod > 0 ? Date().addingTimeInterval(gracePeriod) : nil
            condition.broadcast()
            condition.unlock()
        }

        func waitForCallbacksToDrain() {
            condition.lock()
            while true {
                let graceWindowExpired = stopAcceptanceDeadline.map { Date() >= $0 } ?? true
                if activeCallbacks == 0, graceWindowExpired {
                    stopAcceptanceDeadline = nil
                    condition.unlock()
                    return
                }

                if activeCallbacks == 0, let deadline = stopAcceptanceDeadline {
                    _ = condition.wait(until: deadline)
                } else {
                    condition.wait()
                }
            }
        }
    }

    private let queue = DispatchQueue(label: "com.mouthtype.audiocapture", qos: .userInteractive)
    private let tapDrainCoordinator = TapDrainCoordinator()
    /// 80ms 宽限期 - 基于音频缓冲排空时间的经验值
    /// 允许进行中的音频回调在停止前完成写入
    private let tapStopGracePeriod: TimeInterval = AudioConfiguration.tapStopGracePeriod
    private var engine: AVAudioEngine?
    private var outputFileURL: URL?
    private var streamingHandler: ((Data) -> Void)?
    private var preferredDeviceId: String?
    private var vadProcessor: VADProcessor?
    private var ringBuffer: AudioRingBuffer?
    private var isVADMode = false
    // MARK: - 录音缓冲 (内存缓冲模式 - Mouthpiece 模式)
    // 录音过程中仅收集到内存，停止时一次性写入 WAV 文件
    private var recordingPCMData = Data()
    private var recordingFormat: AVAudioFormat?
    private let pcmLock = NSLock()

    var onAudioLevel: (@Sendable (Float) -> Void)?
    var onVADStateChange: (@Sendable (VADProcessor.VADState) -> Void)?
    var preferredMicDeviceId: String? {
        get { preferredDeviceId }
        set {
            preferredDeviceId = newValue
            restartAudioEngineWithNewDevice()
        }
    }

    // MARK: - Device Loss Detection

    private var deviceChangeObserver: NSObjectProtocol?
    private var currentDeviceID: AudioDeviceID?
    var onDeviceLost: (@Sendable () -> Void)?

    private func setupDeviceChangeObserver() {
        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVAudioEngineConfigurationChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAudioDeviceChange()
        }
    }

    private func handleAudioDeviceChange() {
        queue.async { [weak self] in
            guard let self else { return }

            // Check if current device is still available
            if let deviceId = currentDeviceID {
                let availableDevices = Self.availableAudioDevices()
                if !availableDevices.contains(deviceId) {
                    // Device lost - notify and restart with default
                    DispatchQueue.main.async { [weak self] in
                        self?.onDeviceLost?()
                    }
                    audioCaptureLog.warning("Audio device lost: \(deviceId)")
                }
            }
        }
    }

    private static func availableAudioDevices() -> Set<AudioDeviceID> {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else {
            return []
        }

        return Set(devices)
    }

    private func captureDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }
        return deviceID
    }

    private func restartAudioEngineWithNewDevice() {
        // If engine is running, restart it with the new device
        let wasStreaming = streamingHandler != nil
        let handler = streamingHandler
        if wasStreaming {
            stopStreaming()
            if let handler {
                try? startStreaming(handler: handler)
            }
        }
    }

    // MARK: - Tap Mode (record to file - memory buffer pattern)

    func startRecording(to directory: URL? = nil) throws -> URL {
        audioCaptureLog.info("[startRecording] 开始录音，directory=\(directory?.path ?? "default")")
        stopStreaming()

        let engine = AVAudioEngine()

        // Configure preferred device if set
        if let deviceId = preferredDeviceId {
            configureInputDevice(engine: engine, deviceId: deviceId)
        }

        let node = engine.inputNode
        let inputFormat = node.outputFormat(forBus: 0)
        audioCaptureLog.info("[startRecording] 输入节点格式：采样率=\(inputFormat.sampleRate), 声道数=\(inputFormat.channelCount)")

        if inputFormat.channelCount == 0 {
            audioCaptureLog.error("[startRecording] 声道数为 0，无法录音！")
            throw AudioCaptureError.engineStartFailed
        }

        // 创建 16kHz 单声道目标格式（ASR 引擎需要）
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: AudioConfiguration.targetSampleRate, channels: AudioConfiguration.channels, interleaved: true)!
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            audioCaptureLog.error("[startRecording] 无法创建格式转换器")
            throw AudioCaptureError.engineStartFailed
        }

        // 创建临时文件 URL（但先不写数据，仅保存路径）
        let tempDir = directory ?? FileManager.default.temporaryDirectory
        let fileName = "mouthtype_\(Int(Date().timeIntervalSince1970)).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // 保存文件路径供 stopRecording 使用
        outputFileURL = fileURL

        // 重置录音缓冲
        pcmLock.lock()
        recordingPCMData.removeAll(keepingCapacity: true)
        pcmLock.unlock()
        tapDrainCoordinator.startSession()
        audioCaptureLog.info("[startRecording] 缓冲区已重置，文件路径=\(fileURL.path)")

        // 安装 Tap - 转换为 16kHz 后收集到内存，无文件 I/O
        node.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] inputBuffer, _ in
            guard let self else {
                audioCaptureLog.error("[tap] self 为 nil，返回")
                return
            }

            let accepted = self.tapDrainCoordinator.beginCallback()
            if !accepted {
                return
            }
            defer { self.tapDrainCoordinator.endCallback() }

            // 格式转换：inputFormat → 16kHz Int16 单声道
            let outputBufferSize = AVAudioFrameCount(
                Double(inputBuffer.frameLength) * AudioConfiguration.targetSampleRate / inputFormat.sampleRate
            )
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputBufferSize) else {
                return
            }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard status != .error else {
                audioCaptureLog.error("[tap] 格式转换失败：\(error?.localizedDescription ?? "unknown")")
                return
            }

            // 追加转换后的 16kHz PCM 数据到内存缓冲
            // 注意：pcmLock 必须在 tapDrainCoordinator 回调内持有，确保停止时不会竞态
            let byteCount = Int(outputBuffer.frameLength) * 2
            if byteCount > 0 {
                let audioBufferList = outputBuffer.audioBufferList.pointee.mBuffers
                guard let mData = audioBufferList.mData else { return }
                // 使用 try? 避免死锁 - 如果无法立即获得锁则跳过本次写入
                // 这发生在 stopRecording() 已持有锁等待回调完成的极端情况
                if pcmLock.try() {
                    self.recordingPCMData.append(Data(bytes: mData.assumingMemoryBound(to: UInt8.self), count: byteCount))
                    pcmLock.unlock()
                } else {
                    // 锁被占用，跳过本次写入（数据丢失可接受，因为正在停止录音）
                    audioCaptureLog.debug("[tap] pcmLock 被占用，跳过本次写入")
                }
            }

            let level = self.calculateLevel(buffer: outputBuffer)
            self.onAudioLevel?(level)
        }
        audioCaptureLog.info("[startRecording] Tap 已安装（内存缓冲模式，16kHz 转换）")

        try engine.start()
        self.engine = engine
        audioCaptureLog.info("[startRecording] AVAudioEngine 启动成功")

        return fileURL
    }

    func stopRecording() -> URL? {
        return queue.sync { [weak self] in
            guard let self else { return nil }
            audioCaptureLog.info("[stopRecording] 开始停止录音，engine=\(self.engine != nil ? "存在" : "nil"), pendingData=\(self.recordingPCMData.count) 字节")

            // 1. 停止接受新的回调，但保留宽限期让正在进行的回调完成
            tapDrainCoordinator.beginStopping(gracePeriod: tapStopGracePeriod)
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil

            // 2. 等待所有进行中的回调完成
            tapDrainCoordinator.waitForCallbacksToDrain()

            // 3. 收集最终的 PCM 数据（拷贝数据，避免竞争）
            pcmLock.lock()
            let finalPCMData = recordingPCMData
            pcmLock.unlock()

            audioCaptureLog.info("[stopRecording] 最终 PCM 数据=\(finalPCMData.count) 字节")

            // 4. 单次原子写入 WAV 文件
            guard let fileURL = outputFileURL else {
                audioCaptureLog.error("[stopRecording] outputFileURL 为 nil")
                return nil
            }

            do {
                try writeWAVFile(pcmData: finalPCMData, to: fileURL)
                audioCaptureLog.info("[stopRecording] WAV 写入成功：\(fileURL.path), \(finalPCMData.count) 字节")

                // 5. 清理内存
                pcmLock.lock()
                recordingPCMData.removeAll(keepingCapacity: true)
                pcmLock.unlock()

                let url = outputFileURL
                outputFileURL = nil
                return url

            } catch {
                audioCaptureLog.error("[stopRecording] WAV 写入失败：\(error.localizedDescription)")
                // 清理失败的临时文件
                if let url = outputFileURL {
                    try? FileManager.default.removeItem(at: url)
                    audioCaptureLog.info("[stopRecording] 已清理临时文件：\(url.lastPathComponent)")
                }
                outputFileURL = nil
                return nil
            }
        }
    }

    // MARK: - WAV File Writing (atomic write - Mouthpiece pattern)

    /// 原子性写入 WAV 文件（44 字节 Header + PCM Data）
    private func writeWAVFile(pcmData: Data, to url: URL) throws {
        // 1. 计算 WAV 参数
        let sampleRate: Double = AudioConfiguration.targetSampleRate  // 固定 16kHz for ASR
        let channels = AudioConfiguration.channels        // 单声道 (AVAudioChannelCount)
        let bitsPerSample: UInt16 = AudioConfiguration.bitsPerSample  // Int16 PCM
        let bytesPerSample = 2
        let dataSize = pcmData.count

        // 2. 构建 WAV Header (44 bytes)
        var header = Data()

        // RIFF chunk descriptor
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])  // "RIFF"
        var riffChunkSize = UInt32(36 + dataSize).littleEndian
        withUnsafeBytes(of: &riffChunkSize) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45])  // "WAVE"

        // fmt subchunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])  // "fmt "
        var subchunk1Size = UInt32(16).littleEndian  // PCM format
        withUnsafeBytes(of: &subchunk1Size) { header.append(contentsOf: $0) }
        var audioFormat = UInt16(1).littleEndian  // PCM = 1
        withUnsafeBytes(of: &audioFormat) { header.append(contentsOf: $0) }
        var numChannels = channels.littleEndian
        withUnsafeBytes(of: &numChannels) { header.append(contentsOf: $0) }
        var sampleRateLE = UInt32(sampleRate).littleEndian
        withUnsafeBytes(of: &sampleRateLE) { header.append(contentsOf: $0) }
        var byteRate = UInt32(sampleRate * Double(channels) * Double(bytesPerSample)).littleEndian
        withUnsafeBytes(of: &byteRate) { header.append(contentsOf: $0) }
        var blockAlign = UInt16(UInt16(channels) * UInt16(bytesPerSample)).littleEndian
        withUnsafeBytes(of: &blockAlign) { header.append(contentsOf: $0) }
        var bitsPerSampleLE = bitsPerSample.littleEndian
        withUnsafeBytes(of: &bitsPerSampleLE) { header.append(contentsOf: $0) }

        // data subchunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])  // "data"
        var subchunk2Size = UInt32(dataSize).littleEndian
        withUnsafeBytes(of: &subchunk2Size) { header.append(contentsOf: $0) }

        // 3. 一次性写入文件
        var fileData = header
        fileData.append(pcmData)
        try fileData.write(to: url)

        let headerSize = 44
        audioCaptureLog.info("[writeWAVFile] 写入成功：header=\(headerSize)bytes, data=\(dataSize)bytes, total=\(fileData.count)bytes")
    }

    // MARK: - File Writing (deprecated - kept for compatibility)

    /// 将缓冲的 PCM 数据写入文件（已废弃，仅保留用于 streaming 模式）
    private func flushPCMData(sync: Bool = false) {
        // 内存缓冲模式下，此方法不再使用
        audioCaptureLog.debug("[flushPCMData] 内存缓冲模式下已废弃")
    }

    // MARK: - Streaming Mode (feed PCM chunks to handler)

    /// Start streaming mode: instead of writing to a file, call the handler with PCM chunks.
    /// For use with Bailian WebSocket streaming.
    func startStreaming(handler: @escaping (Data) -> Void) throws {
        try startStreaming(vadEnabled: false, handler: handler)
    }

    /// Start streaming mode with VAD (Voice Activity Detection)
    /// - Parameters:
    ///   - vadEnabled: Enable VAD for voice-activated streaming
    ///   - handler: Callback for PCM audio chunks (only called when voice active)
    func startStreaming(vadEnabled: Bool, handler: @escaping (Data) -> Void) throws {
        // 停止当前录音/streaming（但不要用 stopRecording 的 WAV 写入逻辑）
        stopStreaming()

        self.streamingHandler = handler
        self.isVADMode = vadEnabled

        if vadEnabled {
            self.vadProcessor = VADProcessor()
            self.ringBuffer = AudioRingBuffer(durationMs: 500)

            self.vadProcessor?.onVoiceDetected = { [weak self] in
                // Emit pre-roll buffer when voice detected
                if let preRollData = self?.ringBuffer?.readAndResetAsPCM() {
                    self?.streamingHandler?(preRollData)
                }
            }

            self.vadProcessor?.onStateChange = { [weak self] state in
                DispatchQueue.main.async {
                    self?.onVADStateChange?(state)
                }
            }
        }

        let engine = AVAudioEngine()

        // Configure preferred device if set
        if let deviceId = preferredDeviceId {
            configureInputDevice(engine: engine, deviceId: deviceId)
        }

        // Store device ID for loss detection
        currentDeviceID = captureDeviceID()
        if deviceChangeObserver == nil {
            setupDeviceChangeObserver()
        }

        let node = engine.inputNode
        // Resample to 16kHz mono for ASR
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: AudioConfiguration.targetSampleRate, channels: AudioConfiguration.channels)!

        // Install tap on input format, then convert
        let inputFormat = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.engineStartFailed
        }

        node.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] inputBuffer, _ in
            guard let self else { return }

            let outputBufferSize = AVAudioFrameCount(
                Double(inputBuffer.frameLength) * AudioConfiguration.targetSampleRate / inputFormat.sampleRate
            )
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputBufferSize) else {
                return
            }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if status != .error, let channelData = outputBuffer.floatChannelData?[0] {
                let frameCount = Int(outputBuffer.frameLength)

                if self.isVADMode, let vad = self.vadProcessor {
                    // VAD mode - process through VAD
                    vad.process(outputBuffer) { pcmChunk in
                        self.streamingHandler?(pcmChunk)
                    }
                } else {
                    // Standard mode - emit all audio
                    let byteCount = frameCount * 2 // Int16 = 2 bytes
                    var pcmData = Data(capacity: byteCount)
                    for i in 0..<frameCount {
                        let sample = max(-1.0, min(1.0, channelData[i]))
                        let int16 = Int16(sample * 32767.0)
                        pcmData.append(contentsOf: withUnsafeBytes(of: int16.bigEndian) { Array($0) })
                    }
                    self.streamingHandler?(pcmData)
                }

                // Also report audio level
                var sum: Float = 0
                for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
                let level = sqrt(sum / Float(frameCount))
                self.onAudioLevel?(level)
            }
        }

        try engine.start()
        self.engine = engine

        if vadEnabled {
            audioCaptureLog.info("Streaming started with VAD mode")
        } else {
            audioCaptureLog.info("Streaming started (standard mode)")
        }
    }

    func stopStreaming() {
        queue.sync {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
            streamingHandler = nil
            vadProcessor = nil
            ringBuffer = nil
            isVADMode = false
            currentDeviceID = nil
        }
    }

    // MARK: - Helpers

    private func configureInputDevice(engine: AVAudioEngine, deviceId: String) {
        // Note: AVAudioEngine doesn't support device selection on macOS.
        // The preferred device ID is stored for future use or for other audio APIs.
        // For now, we rely on the system default audio device.
        _ = deviceId // Reserved for future implementation
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
        return sqrt(sum / Float(frameCount))
    }
}

enum AudioCaptureError: LocalizedError {
    case fileCreationFailed
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .fileCreationFailed: "创建音频文件失败"
        case .engineStartFailed: "启动音频引擎失败"
        }
    }
}
