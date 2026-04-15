import AppKit
import SwiftUI

final class FloatingCapsuleWindow: NSPanel {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState

        let rect = NSRect(x: 0, y: 0, width: 320, height: 64)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let hostingView = NSHostingView(rootView: FloatingCapsuleView(appState: appState))
        hostingView.frame = rect
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true

        contentView = hostingView
        setFrame(rect, display: true)

        // Center on screen initially
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - rect.width / 2
            let y = screenRect.maxY - rect.height - 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func show() {
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct FloatingCapsuleView: View {
    let appState: AppState
    @AppStorage("activationHotkey") private var activationHotkeyRawValue: String = ActivationHotkey.defaultValue.rawValue
    @State private var previousStreamingText: String = ""
    @State private var textChangeCount: Int = 0

    private var activationHotkey: ActivationHotkey {
        ActivationHotkey(rawValue: activationHotkeyRawValue) ?? .defaultValue
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIcon
                .font(.system(size: 20))
                .accessibilityIdentifier("floatingCapsule.statusIcon")

            // Text preview
            capsuleText

            Spacer()

            // Audio level indicator
            if shouldShowAudioLevel {
                audioLevelBar
                    .accessibilityIdentifier("floatingCapsule.audioLevel")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("floatingCapsule.root")
        .accessibilityLabel(capsuleStatusLabel)
    }

    @ViewBuilder
    private var capsuleText: some View {
        if appState.isRecording {
            if appState.streamingText.isEmpty {
                Text("正在聆听…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("floatingCapsule.text")
            } else {
                // 优化：流式文本添加平滑动画和视觉反馈
                Text(appState.streamingText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeOut(duration: 0.2), value: appState.streamingText)
                    .accessibilityIdentifier("floatingCapsule.text")
            }
        } else if case .processing = appState.dictationState {
            Text("正在处理…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("floatingCapsule.text")
        } else if case .aiProcessing = appState.dictationState {
            Text("正在进行 AI 处理…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("floatingCapsule.text")
        } else if case .error(let msg) = appState.dictationState {
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .lineLimit(1)
                .accessibilityIdentifier("floatingCapsule.text")
        } else {
            let idleText = UITestConfiguration.current.isEnabled ? UITestConfiguration.current.capsuleText : "按住 \(activationHotkey.displayName) 开始听写"
            Text(idleText)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("floatingCapsule.text")
        }
    }

    private var capsuleStatusLabel: String {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.capsuleStatusLabel
        }

        switch appState.dictationState {
        case .listening, .recording:
            return "recording"
        case .streaming:
            return "streaming"
        case .processing, .aiProcessing:
            return "processing"
        case .error:
            return "error"
        case .idle:
            return "idle"
        }
    }

    private var shouldShowAudioLevel: Bool {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.shouldShowCapsuleAudioLevel
        }
        return appState.isRecording
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.dictationState {
        case .listening, .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        case .streaming:
            // 优化：流式模式下添加脉冲动画和颜色渐变
            Image(systemName: "mic.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse.byLayer)
        case .processing, .aiProcessing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(1.2)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .idle:
            Image(systemName: "mic")
                .foregroundStyle(.secondary)
        }
    }

    private var audioLevelBar: some View {
        Capsule()
            .fill(.blue.opacity(0.6))
            .frame(width: 4, height: max(4, min(40, CGFloat(appState.audioLevel) * 50)))
            .animation(.easeInOut(duration: 0.05), value: appState.audioLevel)
    }
}
