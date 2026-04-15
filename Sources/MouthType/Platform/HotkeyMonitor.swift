import Cocoa
import Foundation
import os

private let hotkeyLog = RedactedLogger(subsystem: "com.mouthtype", category: "HotkeyMonitor")

@MainActor
final class HotkeyMonitor: @unchecked Sendable {
    private final class EventTapContext {
        weak var monitor: HotkeyMonitor?

        init(monitor: HotkeyMonitor? = nil) {
            self.monitor = monitor
        }
    }

    private let appState: AppState
    private let settings = AppSettings.shared
    private let audioCapture = AudioCapture()
    private let whisperProvider = WhisperProvider()
    private let paraformerProvider = ParaformerProvider()
    private let pasteService = PasteService()
    private let bailianProvider = BailianStreamingProvider()
    private let aiProvider = BailianAIProvider()
    private let contextLearning = ContextLearningService.shared
    private let stabilizer = TranscriptStabilizer()
    private let postProcessExecutor = PostProcessExecutor()

    private var isKeyDown = false
    private var isCloudFallbackMode = false
    private var pendingStreamingFinalText: String?
    private var didPromptInputMonitoring = false
    private nonisolated(unsafe) var eventTap: CFMachPort?
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var eventTapRunLoop: CFRunLoop?
    private var tapRecordingURL: URL?
    private var hotkeyObserver: NSObjectProtocol?
    private var appliedHotkey: ActivationHotkey
    private var pendingHotkeyReload = false
    private let eventTapContext: Unmanaged<EventTapContext>
    private var stabilizerSessionId: String = ""

    private var selectedHotkey: ActivationHotkey {
        appliedHotkey
    }

    init(appState: AppState) {
        self.appState = appState
        self.appliedHotkey = settings.activationHotkey
        self.eventTapContext = Unmanaged.passRetained(EventTapContext())
        self.eventTapContext.takeUnretainedValue().monitor = self

        // Wire audio level to appState for UI display
        audioCapture.onAudioLevel = { [weak appState] level in
            Task { @MainActor in
                appState?.setAudioLevel(level)
            }
        }

        setupMonitoring()
        observeHotkeyChanges()
    }

    deinit {
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
        eventTapContext.takeUnretainedValue().monitor = nil
        removeEventTap()
        eventTapContext.release()
    }

    func stop() {
        if Thread.isMainThread {
            stopOnMainThread()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.stopOnMainThread()
            }
        }
    }

    private func stopOnMainThread() {
        removeEventTap()
        Task { @MainActor [weak self] in
            await self?.resetSessionState(transitionToIdle: false)
        }
    }

    // MARK: - Setup

    private func setupMonitoring() {
        if !PasteService.checkInputMonitoring() {
            if !didPromptInputMonitoring {
                didPromptInputMonitoring = true
                PasteService.promptInputMonitoring()
                hotkeyLog.info("Input Monitoring permission needed.")
            }
            retryMonitoringSetup()
            return
        }

        installEventTap()
    }

    private func retryMonitoringSetup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.setupMonitoring()
        }
    }

    private func observeHotkeyChanges() {
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let configuredHotkey = self.settings.activationHotkey
                guard configuredHotkey != self.appliedHotkey else { return }

                if self.appState.dictationState == .idle {
                    self.appliedHotkey = configuredHotkey
                    self.pendingHotkeyReload = false
                    self.reloadMonitoring()
                } else {
                    self.pendingHotkeyReload = true
                }
            }
        }
    }

    private func applyPendingHotkeyReloadIfNeeded() {
        guard pendingHotkeyReload, appState.dictationState == .idle else { return }
        appliedHotkey = settings.activationHotkey
        pendingHotkeyReload = false
        reloadMonitoring()
    }

    private func reloadMonitoring() {
        if Thread.isMainThread {
            reloadMonitoringOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reloadMonitoringOnMainThread()
            }
        }
    }

    private func reloadMonitoringOnMainThread() {
        removeEventTap()
        Task { @MainActor [weak self] in
            await self?.resetSessionState(transitionToIdle: false)
            self?.setupMonitoring()
        }
    }

    private nonisolated func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource, let runLoop = eventTapRunLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [source] in
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopWakeUp(runLoop)
            runLoopSource = nil
            eventTapRunLoop = nil
        } else {
            runLoopSource = nil
            eventTapRunLoop = nil
        }
    }

    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<EventTapContext>.fromOpaque(refcon).takeUnretainedValue()
                guard let monitor = context.monitor else { return Unmanaged.passUnretained(event) }
                monitor.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: eventTapContext.toOpaque()
        ) else {
            hotkeyLog.error("Failed to install event tap. Check Input Monitoring permission.")
            retryMonitoringSetup()
            return
        }

        let currentRunLoop = CFRunLoopGetCurrent()
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.eventTapRunLoop = currentRunLoop
        CFRunLoopAddSource(currentRunLoop, runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        hotkeyLog.info("Listening for \(self.selectedHotkey.displayName)")
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == selectedHotkey.keyCode else { return }

        let modifierNowPresent = event.flags.contains(selectedHotkey.modifierFlag)

        if modifierNowPresent && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in
                self?.handleKeyDown()
            }
        } else if !modifierNowPresent && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in self?.handleKeyUp() }
        }
    }

    // MARK: - Key Actions

    private func handleKeyDown() {
        // 如果当前是错误状态，先恢复再开始新会话
        if case .error = appState.dictationState {
            appState.recoverFromError()
        }
        guard appState.dictationState == .idle else { return }

        isCloudFallbackMode = false
        pendingStreamingFinalText = nil
        tapRecordingURL = nil

        // Determine which ASR provider to use based on settings
        switch settings.asrProvider {
        case .localWhisper:
            startWhisperTapMode()
        case .localParaformer:
            startParaformerTapMode()
        case .bailianStreaming, .bailian:
            startCloudFallbackMode()
        }
    }

    private func startWhisperTapMode() {
        if let availabilityError = whisperProvider.availabilityError {
            if startCloudFallbackIfNeeded(availabilityError) { return }
            appState.transitionToError(availabilityError.localizedDescription)
            return
        }

        do {
            let url = try audioCapture.startRecording()
            tapRecordingURL = url
            appState.transition(to: .recording)
            hotkeyLog.info("Recording started (Whisper tap mode)")
        } catch {
            appState.transitionToError("麦克风错误：\(error.localizedDescription)")
        }
    }

    private func startParaformerTapMode() {
        hotkeyLog.info("[startParaformerTapMode] 开始")
        if let availabilityError = paraformerProvider.availabilityError {
            hotkeyLog.error("[startParaformerTapMode] Paraformer 不可用：\(availabilityError.localizedDescription)")
            if startCloudFallbackIfNeeded(availabilityError) { return }
            appState.transitionToError(availabilityError.localizedDescription)
            return
        }

        do {
            let url = try audioCapture.startRecording()
            tapRecordingURL = url
            appState.transition(to: .recording)
            hotkeyLog.info("[startParaformerTapMode] 录音开始，url=\(url.path)")
        } catch {
            hotkeyLog.error("[startParaformerTapMode] 录音失败：\(error.localizedDescription)")
            appState.transitionToError("麦克风错误：\(error.localizedDescription)")
        }
    }

    private func startCloudFallbackMode() {
        guard bailianProvider.isAvailable else {
            appState.transitionToError("未配置 Bailian API key")
            return
        }
        isCloudFallbackMode = true
        startBailianStream()
        let hotwordsCount = settings.cloudFallbackHotwordsEnabled ? contextLearning.getHotwords(for: .cloudFallback).count : 0
        hotkeyLog.info("Recording started (Bailian cloud mode, \(hotwordsCount) hotwords)")
    }

    private func handleKeyUp() {
        guard appState.isRecording else { return }

        if isCloudFallbackMode {
            stopStreamingAndPaste()
        } else {
            tapTranscribe()
        }
    }

    @MainActor
    private func recoverFromErrorState() async {
        await resetSessionState(transitionToIdle: true)
    }

    private func startCloudFallbackIfNeeded(_ recordingError: Error) -> Bool {
        // Check if any local ASR is unavailable and Bailian is available
        let localASRUnavailable = whisperProvider.availabilityError != nil
            || paraformerProvider.availabilityError != nil
        guard localASRUnavailable, bailianProvider.isAvailable else {
            return false
        }

        isCloudFallbackMode = true
        startBailianStream()
        hotkeyLog.info("Local ASR unavailable, falling back to Bailian streaming: \(recordingError.localizedDescription)")
        return true
    }

    // MARK: - Bailian Streaming

    private var bailianStreamTask: Task<Void, Never>?
    private var streamStopTask: Task<Void, Never>?
    private var vadSilenceTriggerTask: Task<Void, Never>?

    private func startBailianStream() {
        bailianStreamTask?.cancel()
        bailianStreamTask = Task { [weak self] in
            guard let self else { return }

            do {
                try self.audioCapture.startStreaming { [weak self] pcmData in
                    Task { [weak self] in
                        await self?.bailianProvider.sendAudio(pcmData)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCloudFallbackMode = false
                    self.appState.transitionToError("麦克风错误：\(error.localizedDescription)")
                }
                return
            }

            await MainActor.run {
                self.appState.transition(to: .streaming(""))
            }

            let hotwords = settings.cloudFallbackHotwordsEnabled
                ? contextLearning.getHotwords(for: .cloudFallback)
                : []

            do {
                let stream = try await bailianProvider.startStreaming(hotwords: hotwords)

                for try await segment in stream {
                    await MainActor.run {
                        if segment.isFinal {
                            self.pendingStreamingFinalText = segment.simplifiedText
                        }
                        self.appState.streamingText = segment.simplifiedText
                    }
                }

                await MainActor.run {
                    if !self.appState.streamingText.isEmpty {
                        self.appState.lastTranscription = self.pendingStreamingFinalText ?? self.appState.streamingText
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.isCloudFallbackMode else { return }
                    self.audioCapture.stopStreaming()
                    self.isCloudFallbackMode = false
                    self.pendingStreamingFinalText = nil
                    self.appState.transitionToError("流式转写失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Transcription

    private func tapTranscribe() {
        hotkeyLog.info("[tapTranscribe] 开始，当前 dictationState=\(appState.dictationState), tapRecordingURL=\(tapRecordingURL?.path ?? "nil")")
        let audioURL: URL?
        if appState.dictationState == .recording, let saved = tapRecordingURL {
            hotkeyLog.info("[tapTranscribe] 进入 recording 分支，调用 stopRecording()")
            _ = audioCapture.stopRecording()
            audioURL = saved
        } else {
            hotkeyLog.warning("[tapTranscribe] 进入 else 分支（非 recording 状态或 tapRecordingURL 为 nil），调用 stopRecording()")
            audioURL = audioCapture.stopRecording()
        }
        tapRecordingURL = nil

        hotkeyLog.info("[tapTranscribe] stopRecording 返回 audioURL=\(audioURL?.path ?? "nil")")
        appState.transition(to: .processing)

        Task { @MainActor [weak self] in
            guard let self, let audioURL else {
                hotkeyLog.error("[tapTranscribe] audioURL 为 nil，直接返回 idle")
                self?.appState.transition(to: .idle)
                self?.applyPendingHotkeyReloadIfNeeded()
                return
            }
            hotkeyLog.info("[tapTranscribe] 开始转写，audioURL=\(audioURL.path)")
            do {
                let result: ASRResult
                switch settings.asrProvider {
                case .localWhisper:
                    result = try await whisperProvider.transcribe(audioURL: audioURL)
                case .localParaformer:
                    result = try await paraformerProvider.transcribe(audioURL: audioURL)
                default:
                    hotkeyLog.warning("[tapTranscribe] 未知的 ASR Provider，返回 idle")
                    appState.transition(to: .idle)
                    applyPendingHotkeyReloadIfNeeded()
                    cleanup(audioURL)
                    return
                }
                hotkeyLog.info("[tapTranscribe] 转写完成，result.simplifiedText=\(LogRedaction.redactTranscript(result.simplifiedText.prefix(50).description))")
                guard !result.simplifiedText.isEmpty else {
                    hotkeyLog.warning("[tapTranscribe] 转写结果为空，返回 idle")
                    self.appState.transition(to: .idle)
                    self.applyPendingHotkeyReloadIfNeeded()
                    self.cleanup(audioURL)
                    return
                }
                let text = result.simplifiedText
                self.appState.lastTranscription = text
                hotkeyLog.info("[tapTranscribe] 有有效文本，aiEnabled=\(self.settings.aiEnabled), aiProvider.isAvailable=\(self.aiProvider.isAvailable)")
                if self.settings.aiEnabled, self.aiProvider.isAvailable {
                    try await self.processWithAI(text: text)
                } else {
                    hotkeyLog.info("[tapTranscribe] 准备粘贴文本：\(LogRedaction.redactTranscript(text.prefix(50).description))")
                    HistoryStore.shared.insert(raw: text)
                    do {
                        try await self.pasteService.paste(text: text)
                        hotkeyLog.info("[tapTranscribe] 粘贴成功")
                    } catch {
                        hotkeyLog.error("[tapTranscribe] 粘贴失败：\(error.localizedDescription)")
                        throw error
                    }
                    self.appState.transition(to: .idle)
                    self.applyPendingHotkeyReloadIfNeeded()
                }
            } catch {
                hotkeyLog.error("[tapTranscribe] 错误：\(LogRedaction.redactLogMessage(error.localizedDescription))")
                self.appState.transitionToError(error.localizedDescription)
            }
            self.cleanup(audioURL)
        }
    }

    private func stopStreamingAndPaste() {
        guard streamStopTask == nil else { return }
        let streamTask = bailianStreamTask

        streamStopTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // 关键修复：在停止音频捕获前延迟 150ms，确保 key-up 时的尾音被完整发送
            // 尾音分析：中文音节平均时长 150-250ms，50ms 可能截断韵母尾部
            // 延迟 150ms 可捕获 90%+ 的尾音，同时保持可接受的响应速度
            try? await Task.sleep(for: .milliseconds(150))

            self.audioCapture.stopStreaming()

            // Signal Bailian to start draining; runWebSocket will wait
            // up to 2s for final segments before finishing the stream.
            await self.bailianProvider.stopStreaming()

            // Wait for the stream task to complete naturally (drain + finish)
            await streamTask?.value
            self.bailianStreamTask = nil
            self.streamStopTask = nil
            self.isCloudFallbackMode = false

            let text = (self.pendingStreamingFinalText ?? self.appState.streamingText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.pendingStreamingFinalText = nil
            guard !text.isEmpty else {
                self.appState.transition(to: .idle)
                self.applyPendingHotkeyReloadIfNeeded()
                return
            }

            do {
                self.appState.lastTranscription = text
                if self.settings.aiEnabled, self.aiProvider.isAvailable {
                    try await self.processWithAI(text: text)
                } else {
                    HistoryStore.shared.insert(raw: text)
                    try await self.pasteService.paste(text: text)
                    self.appState.transition(to: .idle)
                    self.applyPendingHotkeyReloadIfNeeded()
                }
            } catch {
                self.appState.transitionToError(error.localizedDescription)
            }
        }
    }

    // MARK: - AI Post-Processing

    private func processWithAI(text: String) async throws {
        appState.transition(to: .aiProcessing)

        let agentName = settings.agentName
        let processedText: String

        do {
            // Use strategy-based post-processing
            processedText = try await postProcessExecutor.process(text, agentName: agentName)
        } catch {
            hotkeyLog.warning("AI processing failed, falling back to raw text: \(error.localizedDescription)")
            // 保存历史记录（即使 AI 失败）
            HistoryStore.shared.insert(raw: text)
            try await pasteService.paste(text: text)
            appState.transition(to: .idle)
            applyPendingHotkeyReloadIfNeeded()
            return
        }

        guard !processedText.isEmpty else {
            // 保存历史记录（即使结果为空）
            HistoryStore.shared.insert(raw: text)
            try await pasteService.paste(text: text)
            appState.transition(to: .idle)
            applyPendingHotkeyReloadIfNeeded()
            return
        }

        try await pasteService.paste(text: processedText)
        HistoryStore.shared.insert(raw: text, processed: processedText)
        appState.transition(to: .idle)
        applyPendingHotkeyReloadIfNeeded()

        // Auto-learn new terms from context
        let hotwords = contextLearning.getHotwords(for: .autoLearn)
        for hotword in hotwords {
            postProcessExecutor.addLearnedTerm(hotword)
        }
    }

    private func detectAIMode(for text: String) -> AIMode {
        let agentName = settings.agentName
        let lowercased = text.lowercased()

        let heyPrefixes = ["hey ", "嘿 "]
        for prefix in heyPrefixes {
            if lowercased.hasPrefix(prefix) {
                let remainder = String(text.dropFirst(prefix.count))
                if remainder.hasPrefix(agentName) {
                    return .agentCommand
                }
            }
        }

        return .cleanup
    }

    @MainActor
    private func resetSessionState(
        transitionToIdle: Bool,
        cancelActiveStopTask: Bool = true
    ) async {
        appState.setAudioLevel(0)
        isKeyDown = false
        isCloudFallbackMode = false
        pendingStreamingFinalText = nil
        if cancelActiveStopTask {
            streamStopTask?.cancel()
        }
        streamStopTask = nil
        bailianStreamTask?.cancel()
        bailianStreamTask = nil
        await bailianProvider.stopStreaming()
        audioCapture.stopStreaming()
        if let recordingURL = audioCapture.stopRecording() {
            cleanup(recordingURL)
        }
        if let pendingURL = tapRecordingURL {
            cleanup(pendingURL)
            tapRecordingURL = nil
        }
        if transitionToIdle {
            appState.transition(to: .idle)
        }
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
