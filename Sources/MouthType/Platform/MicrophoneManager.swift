import Foundation
import AVFoundation
import Combine

final class MicrophoneManager: ObservableObject {
    static let shared = MicrophoneManager()

    init() {}

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let isDefault: Bool
    }

    // MARK: - Device Enumeration

    func availableDevices() -> [Device] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        return discovery.devices.map { device in
            Device(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultDevice?.uniqueID
            )
        }
    }

    func selectDevice(id: String) {
        AppSettings.shared.preferredMicDeviceId = id
    }

    func currentDevice() -> Device? {
        let devices = availableDevices()
        let preferredId = AppSettings.shared.preferredMicDeviceId
        if let preferredId {
            return devices.first { $0.id == preferredId }
        }
        return devices.first { $0.isDefault }
    }

    // MARK: - Audio Level Monitoring

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioNode?
    private var isTesting = false
    private let audioLevelSubject = PassthroughSubject<Float, Never>()
    private var audioLevelContinuation: AsyncThrowingStream<Float, Error>.Continuation?

    /// 音频电平发布器（用于 UI 测试）
    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    /// 开始测试指定设备
    func startTesting(deviceId: String) async throws -> AsyncThrowingStream<Float, Error> {
        guard !isTesting else {
            throw TestError.alreadyTesting
        }

        guard devicesContains(deviceId: deviceId) else {
            throw TestError.deviceNotFound
        }

        isTesting = true

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        // 配置输入
        let input = audioEngine.inputNode
        self.inputNode = input

        let audioFormat = input.inputFormat(forBus: 0)
        let bufferSize = AVAudioFrameCount(audioFormat.sampleRate * 0.05) // 50ms buffer

        // 安装 tap 获取音频电平
        input.installTap(onBus: 0, bufferSize: bufferSize, format: audioFormat) { buffer, _ in
            let level = self.calculateRMS(buffer: buffer)
            Task { @MainActor in
                self.publishAudioLevel(level)
                self.audioLevelContinuation?.yield(level)
            }
        }

        try audioEngine.start()

        return AsyncThrowingStream<Float, Error> { continuation in
            self.audioLevelContinuation = continuation
            continuation.onTermination = { _ in
                Task { @MainActor in
                    self.audioLevelContinuation = nil
                    self.stopTesting()
                }
            }
        }
    }

    /// 停止测试
    func stopTesting() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        audioLevelContinuation?.finish()
        audioLevelContinuation = nil
        isTesting = false
    }

    /// 检查是否正在测试
    var isCurrentlyTesting: Bool {
        isTesting
    }

    // MARK: - Private Methods

    private func devicesContains(deviceId: String) -> Bool {
        if deviceId.isEmpty {
            return true
        }
        return availableDevices().contains { $0.id == deviceId }
    }

    #if DEBUG
    func publishAudioLevelForTesting(_ level: Float) {
        publishAudioLevel(level)
        audioLevelContinuation?.yield(level)
    }

    func calculateRMSForTesting(buffer: AVAudioPCMBuffer) -> Float {
        calculateRMS(buffer: buffer)
    }

    func makeLevelStreamForTesting() -> AsyncThrowingStream<Float, Error> {
        AsyncThrowingStream<Float, Error> { continuation in
            audioLevelContinuation = continuation
            continuation.onTermination = { _ in
                Task { @MainActor in
                    self.audioLevelContinuation = nil
                }
            }
        }
    }

    var isTestingForTesting: Bool {
        isTesting
    }
    #endif

    private func publishAudioLevel(_ level: Float) {
        audioLevelSubject.send(level)
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        if let floatChannelData = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = floatChannelData[i]
                sum += sample * sample
            }
            return sqrt(sum / Float(frameLength))
        }

        if let int16ChannelData = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = Float(int16ChannelData[i]) / Float(Int16.max)
                sum += sample * sample
            }
            return sqrt(sum / Float(frameLength))
        }

        return 0
    }

    // MARK: - Error Types

    enum TestError: LocalizedError {
        case alreadyTesting
        case deviceNotFound
        case cannotStartEngine

        var errorDescription: String? {
            switch self {
            case .alreadyTesting: "已经在测试其他设备"
            case .deviceNotFound: "找不到指定的麦克风设备"
            case .cannotStartEngine: "无法启动音频引擎"
            }
        }
    }
}
