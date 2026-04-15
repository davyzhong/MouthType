import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @AppStorage("activationHotkey") private var activationHotkeyRawValue: String = ActivationHotkey.defaultValue.rawValue
    @AppStorage("asrProvider") private var asrProviderRawValue: String = ASRProviderType.localWhisper.rawValue
    @AppStorage("aiEnabled") private var aiEnabled: Bool = false

    private let steps = ["欢迎", "权限", "ASR 引擎", "AI 后处理", "完成"]

    var body: some View {
        VStack(spacing: 20) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            .accessibilityIdentifier("onboarding.progress")

            // Content
            TabView(selection: $currentStep) {
                WelcomeStepView()
                    .tag(0)
                PermissionStepView()
                    .tag(1)
                ASREngineStepView(asrProvider: $asrProviderRawValue)
                    .tag(2)
                AIStepView(aiEnabled: $aiEnabled)
                    .tag(3)
                CompletionStepView {
                    AppSettings.shared.hasCompletedOnboarding = true
                    dismiss()
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                }
                    .tag(4)
            }
            .tabViewStyle(.automatic)
            .frame(height: 300)
            .accessibilityIdentifier("onboarding.steps")

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("上一步") {
                        currentStep -= 1
                    }
                    .accessibilityIdentifier("onboarding.backButton")
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button(currentStep == steps.count - 2 ? "开始使用" : "下一步") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.nextButton")
                }
            }
            .padding()
        }
        .frame(width: 450)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.content")
    }
}

// MARK: - Step Views

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("欢迎使用 MouthType")
                .font(.title)
                .fontWeight(.semibold)

            Text("您的本地语音识别助手")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("按住快捷键即可听写")
                }

                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("本地运行，保护隐私")
                }

                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("AI 后处理，优化文本")
                }
            }
            .padding()
            .background(.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .accessibilityIdentifier("onboarding.step.welcome")
    }
}

struct PermissionStepView: View {
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false

    private func refreshPermissions() {
        accessibilityGranted = PasteService.checkAccessibility()
        inputMonitoringGranted = PasteService.checkInputMonitoring()
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("权限设置")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("onboarding.step.permissions")

            VStack(spacing: 12) {
                PermissionRow(
                    title: "辅助功能",
                    granted: accessibilityGranted,
                    grantedMessage: "已授权 - 支持自动粘贴",
                    deniedMessage: "未授权 - 无法自动粘贴",
                    accessibilityIdentifier: "onboarding.permissions.accessibility"
                ) {
                    PasteService.promptAccessibility()
                }

                PermissionRow(
                    title: "输入监控",
                    granted: inputMonitoringGranted,
                    grantedMessage: "已授权 - 支持全局快捷键",
                    deniedMessage: "未授权 - 无法监听快捷键",
                    accessibilityIdentifier: "onboarding.permissions.inputMonitoring"
                ) {
                    PasteService.promptInputMonitoring()
                }
            }

            Button("刷新权限状态") {
                refreshPermissions()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("onboarding.permissions.refreshButton")

            Text("需要两项权限才能正常使用 MouthType")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { refreshPermissions() }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let grantedMessage: String
    let deniedMessage: String
    let accessibilityIdentifier: String
    let requestAction: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield")
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(granted ? grantedMessage : deniedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button("请求权限") {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.secondary.opacity(0.1))
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct ASREngineStepView: View {
    @Binding var asrProvider: String
    @State private var whisperModel: String = "base"

    private var selectedProvider: ASRProviderType {
        ASRProviderType(rawValue: asrProvider) ?? .localWhisper
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("选择 ASR 引擎")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("onboarding.step.asr")

            Picker("ASR 引擎", selection: $asrProvider) {
                ForEach(ASRProviderType.allCases, id: \.rawValue) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("onboarding.asr.providerPicker")

            if selectedProvider == .localWhisper {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Whisper 模型选择")
                        .font(.headline)
                    Picker("模型", selection: $whisperModel) {
                        Text("Tiny (最快，~75MB)").tag("tiny")
                        Text("Base (推荐，~142MB)").tag("base")
                        Text("Small (质量更好，~466MB)").tag("small")
                        Text("Medium (高质量，~1.5GB)").tag("medium")
                    }
                    .pickerStyle(.radioGroup)

                    Text("模型文件将在首次使用时自动下载")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            Text("本地引擎完全离线运行，云端引擎仅在当地不可用时作为回退")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct AIStepView: View {
    @Binding var aiEnabled: Bool
    @State private var aiModelName: String = "qwen-plus"
    @State private var aiEndpoint: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    @State private var aiApiKey: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Toggle("启用 AI 后处理", isOn: $aiEnabled)
                .font(.headline)
                .accessibilityIdentifier("onboarding.ai.enabledToggle")

            Text(aiEnabled ? "AI 后处理已启用" : "AI 后处理已禁用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.step.ai")

            if aiEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    PasteableTextField(placeholder: "模型名称", text: $aiModelName)

                    PasteableTextField(placeholder: "请求地址", text: $aiEndpoint)

                    PasteableSecureField(placeholder: "API 密钥", text: $aiApiKey)

                    Text("AI 后处理可以优化标点、移除语气词、整理格式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.secondary.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("启用后，转写结果会经过 AI 优化处理")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct CompletionStepView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("设置完成！")
                .font(.title)
                .fontWeight(.semibold)
                .accessibilityIdentifier("onboarding.step.complete")

            VStack(alignment: .leading, spacing: 8) {
                Text("开始使用：")
                    .font(.headline)

                HStack {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                    Text("按住右侧 ⌥ 键开始听写")
                }

                HStack {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(.secondary)
                    Text("松开按键完成转写并粘贴")
                }
            }
            .padding()
            .background(.secondary.opacity(0.1))
            .cornerRadius(8)

            Button("开始使用 MouthType") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.finishButton")
        }
        .padding()
    }
}

#Preview {
    OnboardingView()
}
