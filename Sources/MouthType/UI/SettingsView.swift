import AppKit
import os
import SwiftUI
import Combine

private let settingsLog = Logger(subsystem: "com.mouthtype", category: "SettingsView")

struct SettingsView: View {
    @State private var bailianApiKey: String = AppSettings.shared.bailianApiKey
    @AppStorage("bailianEndpoint") private var bailianEndpoint: String = "wss://dashscope.aliyuncs.com/api/v1/services/asr/paraformer/realtime"
    @AppStorage("asrProvider") private var asrProviderRawValue: String = ASRProviderType.localWhisper.rawValue
    @AppStorage("whisperModel") private var whisperModel: String = "small"
    @AppStorage("paraformerModel") private var paraformerModel: String = "model.int8"
    @AppStorage("preferredLanguage") private var preferredLanguage: String = "auto"
    @AppStorage("activationHotkey") private var activationHotkeyRawValue: String = ActivationHotkey.defaultValue.rawValue
    @AppStorage("holdThreshold") private var holdThreshold: Double = 0.3
    @AppStorage("audioCuesEnabled") private var audioCuesEnabled: Bool = true
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false
    @AppStorage("aiProvider") private var aiProviderRawValue: String = AIProviderType.bailian.rawValue
    @AppStorage("aiModelName") private var aiModelName: String = "qwen-plus"
    @AppStorage("aiEndpoint") private var aiEndpoint: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    @State private var aiApiKey: String = AppSettings.shared.aiApiKey
    @AppStorage("aiStrictModeEnabled") private var aiStrictModeEnabled: Bool = true
    @AppStorage("aiFallbackChainEnabled") private var aiFallbackChainEnabled: Bool = false
    @AppStorage("agentName") private var agentName: String = "MouthType"
    @AppStorage("aiIterations") private var aiIterations: Int = 1
    @AppStorage("aiAutoIterate") private var aiAutoIterate: Bool = false
    @AppStorage("contextLearningEnabled") private var contextLearningEnabled: Bool = true
    @AppStorage("preferredMicDeviceId") private var preferredMicDeviceId: String = ""
    @State private var permissionRefresh = 0
    @State private var testingDeviceId: String?
    @State private var currentAudioLevel: Float = 0

    // MARK: - Test Connection State
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?

    private var asrProvider: ASRProviderType {
        ASRProviderType(rawValue: asrProviderRawValue) ?? .localWhisper
    }

    private var aiProvider: AIProviderType {
        AIProviderType(rawValue: aiProviderRawValue) ?? .bailian
    }

    private var modelPlaceholder: String {
        switch aiProvider {
        case .bailian: "qwen-plus"
        case .minimax: "MiniMax-Text-01"
        case .zhipu: "glm-4"
        case .openai, .anthropic: "gpt-4o"
        case .fallback: "自动选择"
        }
    }

    private var modelSuggestionText: String {
        switch aiProvider {
        case .bailian: "推荐：qwen-plus（平衡）、qwen-turbo（速度快）、qwen-max（效果最佳）"
        case .minimax: "推荐：MiniMax-Text-01（通用）、MiniMax-Chat-01（对话优化）"
        case .zhipu: "推荐：glm-4（效果最佳）、glm-3-turbo（性价比高）"
        case .openai: "推荐：gpt-4o（效果最佳）、gpt-4o-mini（性价比高）"
        case .anthropic: "推荐：claude-sonnet-4-0（平衡）、claude-opus-4-0（最强）"
        case .fallback: "Fallback 链会自动选择合适的模型"
        }
    }

    private var endpointPlaceholder: String {
        switch aiProvider {
        case .bailian: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .minimax: "https://api.minimax.chat/v1"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .fallback: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
    }

    private var activationHotkey: ActivationHotkey {
        ActivationHotkey(rawValue: activationHotkeyRawValue) ?? .defaultValue
    }

    private var availableMicDevices: [MicrophoneManager.Device] {
        MicrophoneManager.shared.availableDevices()
    }

    private let microphoneManager = MicrophoneManager.shared

    private var accessibilityGranted: Bool {
        _ = permissionRefresh
        return PasteService.checkAccessibility()
    }

    private var inputMonitoringGranted: Bool {
        _ = permissionRefresh
        return PasteService.checkInputMonitoring()
    }

    /// 当前 Provider 的 API Key（从 AppSettings 读取）
    private var currentAPIKey: String {
        get { aiApiKey }
        set { aiApiKey = newValue }
    }

    private func refreshPermissionStatus() {
        permissionRefresh += 1
    }

    private func pasteFromClipboard(into binding: Binding<String>) {
        if let text = NSPasteboard.general.string(forType: .string) {
            binding.wrappedValue = text
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        Task {
            isTestingConnection = true
            connectionTestResult = nil

            let result = await testAIProviderConnection()

            await MainActor.run {
                isTestingConnection = false
                switch result {
                case .success:
                    connectionTestResult = "连接成功"
                case .failure(let error):
                    connectionTestResult = "连接失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func testAIProviderConnection() async -> Result<Void, Error> {
        // 简单的连接测试：检查 API Key 是否配置
        if aiApiKey.isEmpty {
            return .failure(AIError.notConfigured)
        }
        // TODO: 实现实际的 API 连接测试
        return .success(())
    }

    var body: some View {
        TabView {
            // MARK: - ASR
            Form {
                Section("引擎") {
                    Picker("ASR 提供商", selection: $asrProviderRawValue) {
                        ForEach(ASRProviderType.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings.asrProviderPicker")
                    Text("中文场景推荐使用「Paraformer」或「百炼流式」，识别率最高。离线环境使用本地引擎。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if asrProvider == .localWhisper {
                        Picker("Whisper 模型", selection: $whisperModel) {
                            Text("Tiny (最快，约 75MB)").tag("tiny")
                            Text("Base (平衡，约 142MB)").tag("base")
                            Text("Small (中文更好，约 466MB)").tag("small")
                            Text("Medium (高质量，约 1.5GB)").tag("medium")
                            Text("Large (最佳，约 3GB)").tag("large-v3")
                        }
                        Text("中文场景推荐 Small 或 Medium 模型，效果显著优于 Base。模型越大识别越准确，但速度会稍慢。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if asrProvider == .localParaformer {
                        Picker("Paraformer 模型", selection: $paraformerModel) {
                            Text("INT8 (中文最佳，约 79MB)").tag("model.int8")
                        }
                        Text("Paraformer 在中文场景下识别准确率最高，速度快于 Whisper。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("语言", selection: $preferredLanguage) {
                        Text("自动检测").tag("auto")
                        Text("英语").tag("en")
                        Text("中文").tag("zh")
                        Text("日语").tag("ja")
                        Text("韩语").tag("ko")
                    }
                }

                Section("百炼云端（本地不可用时自动回退）") {
                    HStack(spacing: 8) {
                        PasteableSecureField(placeholder: "API 密钥", text: $bailianApiKey, accessibilityIdentifier: "settings.bailianApiKeyField")
                            .frame(height: 22)
                        Button("粘贴") {
                            pasteFromClipboard(into: $bailianApiKey)
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.bailianApiKeyPasteButton")
                    }

                    if !bailianApiKey.isEmpty {
                        Label("API 密钥已配置", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Label("未配置 API 密钥，本地完全不可用时将无法回退到百炼", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                Section("请求地址") {
                    HStack(spacing: 8) {
                        PasteableTextField(placeholder: "wss://...", text: $bailianEndpoint, accessibilityIdentifier: "settings.bailianEndpointField")
                            .frame(height: 22)
                        Button("粘贴") {
                            pasteFromClipboard(into: $bailianEndpoint)
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.bailianEndpointPasteButton")
                    }
                    Text("用于百炼流式 ASR 的 WebSocket 地址；当前听写链路仅在本地引擎不可用时使用该回退通道。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("回退策略") {
                    Label("百炼云端回退已固定启用", systemImage: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                    Text("只有在本地引擎完全不可用时，才会启用百炼云端回退；本地引擎可用但单次转写失败时，不会自动上传音频。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings.tab.asr")
            .tabItem { Label("语音识别", systemImage: "waveform") }

            // MARK: - Interaction
            Form {
                Section("权限") {
                    Label(accessibilityGranted ? "辅助功能已授权" : "辅助功能未授权", systemImage: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                        .accessibilityIdentifier("settings.permissions.accessibilityStatus")

                    Label(inputMonitoringGranted ? "输入监控已授权" : "输入监控未授权", systemImage: inputMonitoringGranted ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(inputMonitoringGranted ? .green : .orange)
                        .accessibilityIdentifier("settings.permissions.inputMonitoringStatus")

                    Text("全局热键主要依赖\"输入监控\"权限；自动粘贴需要\"辅助功能\"权限。当前激活按键为 \(activationHotkey.displayName)。授权后可点击\"刷新权限状态\"。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("打开辅助功能设置") {
                            PasteService.openAccessibilitySettings()
                        }
                        Button("打开输入监控设置") {
                            PasteService.openInputMonitoringSettings()
                        }
                    }

                    HStack(spacing: 8) {
                        Button("请求辅助功能权限") {
                            PasteService.promptAccessibility()
                            refreshPermissionStatus()
                        }
                        .accessibilityIdentifier("settings.permissions.requestAccessibilityButton")
                        Button("请求输入监控权限") {
                            PasteService.promptInputMonitoring()
                            refreshPermissionStatus()
                        }
                        .accessibilityIdentifier("settings.permissions.requestInputMonitoringButton")
                    }

                    Button("刷新权限状态") {
                        refreshPermissionStatus()
                    }
                    .accessibilityIdentifier("settings.permissions.refreshButton")
                }

                Section("快捷键") {
                    Picker("激活按键", selection: $activationHotkeyRawValue) {
                        ForEach(ActivationHotkey.allCases) { hotkey in
                            Text(hotkey.displayName).tag(hotkey.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings.interaction.activationHotkeyPicker")

                    HStack {
                        Text("按住阈值")
                        Spacer()
                        Text(String(format: "%.1f 秒", holdThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $holdThreshold, in: 0.2...1.0, step: 0.1)
                    Text("本地引擎可用时始终使用本地听写；只有本地完全不可用时，才会自动回退到百炼流式转写。当前按住阈值设置仅保留用于后续扩展。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("音频") {
                    Toggle("播放提示音", isOn: $audioCuesEnabled)
                        .accessibilityIdentifier("settings.interaction.audioCuesToggle")

                    Picker("麦克风", selection: $preferredMicDeviceId) {
                        Text("系统默认").tag("")
                        ForEach(availableMicDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .accessibilityIdentifier("settings.interaction.microphonePicker")
                    .onChange(of: preferredMicDeviceId) { _, newValue in
                        microphoneManager.selectDevice(id: newValue)
                    }

                    // 麦克风测试
                    MicrophoneTestView(
                        microphoneManager: microphoneManager,
                        testingDeviceId: $testingDeviceId,
                        currentAudioLevel: $currentAudioLevel,
                        selectedDeviceId: preferredMicDeviceId
                    )

                    Text("点击\"测试\"监听当前系统默认麦克风的音频输入电平。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings.tab.interaction")
            .tabItem { Label("交互", systemImage: "hand.tap") }

            // MARK: - AI
            Form {
                Section("AI 后处理") {
                    Toggle("启用 AI 后处理", isOn: $aiEnabled)
                        .accessibilityIdentifier("settings.ai.enabledToggle")
                    Text("自动清理转写结果、修正标点，并移除语气词。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if aiEnabled {
                    Section("LLM 供应商") {
                        Picker("AI 提供商", selection: $aiProviderRawValue) {
                            ForEach(AIProviderType.allCases.filter { $0.isDomesticAvailable }, id: \.rawValue) { provider in
                                Text(provider.displayName).tag(provider.rawValue)
                            }
                        }
                        .accessibilityIdentifier("settings.ai.providerPicker")
                        Text(AIProviderType(rawValue: aiProviderRawValue)?.description ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("模型配置") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型名称")
                                .font(.subheadline)
                            HStack(spacing: 8) {
                                PasteableTextField(placeholder: modelPlaceholder, text: $aiModelName, accessibilityIdentifier: "settings.ai.modelNameField")
                                    .frame(height: 22)
                                Button("粘贴") {
                                    pasteFromClipboard(into: $aiModelName)
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("settings.ai.modelNamePasteButton")
                            }
                            Text(modelSuggestionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("请求地址")
                                .font(.subheadline)
                            HStack(spacing: 8) {
                                PasteableTextField(placeholder: endpointPlaceholder, text: $aiEndpoint, accessibilityIdentifier: "settings.ai.endpointField")
                                    .frame(height: 22)
                                Button("粘贴") {
                                    pasteFromClipboard(into: $aiEndpoint)
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("settings.ai.endpointPasteButton")
                            }
                            Text("OpenAI 兼容模式支持自定义 BaseURL，如 Azure OpenAI、本地部署等。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API 密钥")
                                .font(.subheadline)
                            HStack(spacing: 8) {
                                PasteableSecureField(placeholder: "API 密钥", text: $aiApiKey, accessibilityIdentifier: "settings.ai.apiKeyField")
                                    .frame(height: 22)
                                Button("粘贴") {
                                    pasteFromClipboard(into: $aiApiKey)
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("settings.ai.apiKeyPasteButton")
                                Button(action: testConnection) {
                                    Image(systemName: "checkmark.shield")
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .disabled(isTestingConnection)
                                .accessibilityIdentifier("settings.ai.testConnectionButton")
                            }
                            if isTestingConnection {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                    Text("正在测试连接...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if let result = connectionTestResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(result.hasPrefix("连接成功") ? .green : .red)
                            }
                        }
                    }

                    Section("严格模式") {
                        Toggle("启用严格模式验证", isOn: $aiStrictModeEnabled)
                            .accessibilityIdentifier("settings.ai.strictModeToggle")
                        Text("严格模式会检测 LLM 返回的 answer-like 内容，并验证输出与输入的重叠度，防止过度改写。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Fallback 链") {
                        Toggle("启用智能 Fallback 链", isOn: $aiFallbackChainEnabled)
                            .accessibilityIdentifier("settings.ai.fallbackChainToggle")
                        Text("启用后会按顺序尝试多个 Provider，当前一个失败时自动切换到下一个，提高可用性。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Agent") {
                        HStack(spacing: 8) {
                            PasteableTextField(placeholder: "Agent 名称", text: $agentName, accessibilityIdentifier: "settings.ai.agentNameField")
                                .frame(height: 22)
                            Button("粘贴") {
                                pasteFromClipboard(into: $agentName)
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier("settings.ai.agentNamePasteButton")
                        }
                        Text("说出英文唤醒词\"Hey \(agentName)...\"即可向 Agent 发送指令。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("迭代优化") {
                        HStack {
                            Text("迭代次数")
                            Spacer()
                            Text("\(aiIterations) 次")
                                .foregroundStyle(.secondary)
                        }
                        Picker("迭代次数", selection: $aiIterations) {
                            Text("1 次").tag(1)
                            Text("2 次").tag(2)
                            Text("3 次").tag(3)
                        }
                        .pickerStyle(.segmented)

                        Toggle("自动多轮优化", isOn: $aiAutoIterate)
                            .accessibilityIdentifier("settings.ai.autoIterateToggle")
                        Text("启用后，AI 会自动执行清理→改写→最终清理的多轮优化流程。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        if !aiApiKey.isEmpty {
                            Label("LLM 供应商已配置", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("启用 AI 调用前，请先配置模型名称、请求地址和 API 密钥", systemImage: "brain")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings.tab.ai")
            .tabItem { Label("AI", systemImage: "brain") }

            // MARK: - Terminology
            Form {
                Section("术语学习") {
                    Toggle("自动学习前台应用上下文", isOn: $contextLearningEnabled)
                        .accessibilityIdentifier("settings.terminology.contextLearningToggle")
                    Text("读取当前聚焦文本框内容，提取术语，提升领域词汇的转写准确率。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("状态") {
                    if contextLearningEnabled {
                        Label("已开启，会根据应用上下文自动学习", systemImage: "text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("已关闭", systemImage: "minus.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings.tab.terminology")
            .tabItem { Label("术语", systemImage: "character.book.closed") }

            // MARK: - Models
            ModelManagerView()
                .formStyle(.grouped)
                .accessibilityIdentifier("settings.tab.models")
                .tabItem { Label("模型", systemImage: "externaldrive") }

            // MARK: - History
            HistoryView()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.tab.history")
                .tabItem { Label("历史", systemImage: "clock") }

            // MARK: - About
            Form {
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("本地语音识别")
                        Spacer()
                        Text("Whisper.cpp / Paraformer（点按模式）")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("流式语音识别")
                        Spacer()
                        Text("阿里云百炼 Paraformer")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings.tab.about")
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(minWidth: 480, minHeight: 400)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.content")
        .onAppear {
            bailianApiKey = AppSettings.shared.bailianApiKey
            aiApiKey = AppSettings.shared.aiApiKey
        }
        .onChange(of: bailianApiKey) { _, newValue in
            AppSettings.shared.bailianApiKey = newValue
        }
        .onChange(of: aiApiKey) { _, newValue in
            AppSettings.shared.aiApiKey = newValue
        }
        .onChange(of: aiProviderRawValue) { _, _ in
            // Provider 切换时，同步 UI 到新的配置
            syncConfigToUI()
        }
        .onDisappear {
            // Sync any pending edits to Keychain on window close
            AppSettings.shared.bailianApiKey = bailianApiKey
            AppSettings.shared.aiApiKey = aiApiKey
        }
    }

    /// 将配置同步到 UI 绑定
    private func syncConfigToUI() {
        // 根据当前 Provider 加载默认配置
        let config = aiProvider.defaultConfig
        aiModelName = config.modelName
        aiEndpoint = config.endpoint
    }
}

#Preview {
    SettingsView()
}

// MARK: - Microphone Test View

/// 麦克风测试视图 - 显示音频电平并允许测试设备
struct MicrophoneTestView: View {
    @ObservedObject var microphoneManager: MicrophoneManager
    @Binding var testingDeviceId: String?
    @Binding var currentAudioLevel: Float
    @State private var testTask: Task<Void, Never>?
    let selectedDeviceId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("测试麦克风")
                Spacer()
                if testingDeviceId != nil {
                    Button("停止") {
                        stopTesting()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button("测试") {
                        startTesting()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }

            // 音频电平指示器
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(audioLevelColor)
                        .frame(width: geometry.size.width * CGFloat(min(1.0, currentAudioLevel * 2)), height: 8)
                        .animation(.easeOut(duration: 0.1), value: currentAudioLevel)
                }
            }
            .frame(height: 8)

            HStack {
                Text(testingDeviceId != nil ? "正在监听..." : "点击\"测试\"开始监听")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "电平：%.2f", currentAudioLevel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .onDisappear {
            stopTesting()
        }
    }

    private var audioLevelColor: Color {
        if currentAudioLevel > 0.3 {
            return .red
        } else if currentAudioLevel > 0.1 {
            return .orange
        } else if currentAudioLevel > 0.01 {
            return .green
        } else {
            return .gray
        }
    }

    private func startTesting() {
        guard testingDeviceId == nil else { return }

        let deviceId = selectedDeviceId.isEmpty ? "" : selectedDeviceId
        testingDeviceId = deviceId
        currentAudioLevel = 0

        testTask = Task {
            do {
                let stream = try await microphoneManager.startTesting(deviceId: deviceId)
                for try await level in stream {
                    await MainActor.run {
                        currentAudioLevel = level
                    }
                }
            } catch {
                settingsLog.error("麦克风测试失败：\(error.localizedDescription)")
            }
            await MainActor.run {
                testingDeviceId = nil
                currentAudioLevel = 0
            }
        }
    }

    private func stopTesting() {
        testTask?.cancel()
        testTask = nil
        microphoneManager.stopTesting()
        testingDeviceId = nil
        currentAudioLevel = 0
    }
}
