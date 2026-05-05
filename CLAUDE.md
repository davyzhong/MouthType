# MouthType Technical Reference for AI Assistants

This document provides comprehensive technical details about the MouthType project architecture for AI assistants working on the codebase.

## Project Overview

MouthType is a native macOS dictation application built with Swift and SwiftUI. It uses whisper.cpp for local speech-to-text transcription and supports cloud processing via multiple AI providers (OpenAI, Bailian/Aliyun, etc.). The app features a floating capsule UI for dictation and a WebKit WebView-based settings panel.

## Architecture Overview

### Core Technologies
- **Frontend UI**: SwiftUI (floating capsule) + WebKit WebView (settings panel)
- **Desktop Framework**: Native macOS app (Swift Package Manager)
- **Database**: SQLite.swift for local transcription history
- **Speech Processing**: whisper.cpp (local) + multiple cloud providers
- **Audio Processing**: AVFoundation + custom audio pipeline

### Key Architectural Decisions

1. **Dual UI Architecture**:
   - Floating Capsule: Minimal overlay for dictation (always on top, draggable)
   - Settings Panel: Full settings interface via WebKit WebView
   - WebView communicates with native code via preload.js bridge

2. **Process Separation**:
   - Main App: Swift/SwiftUI native code
   - WebView: HTML/JS settings interface
   - Preload Script: Secure bridge between WebView and native app

3. **Audio Pipeline**:
   - AVAudioEngine → AudioBuffer → VAD processing → ASR provider
   - Supports multiple ASR backends: Whisper (local), Bailian (cloud), etc.

## File Structure and Responsibilities

### Main App Files

- **MouthTypeApp.swift**: Application entry point, initializes all services
- **preload.js**: WebView bridge exposing safe native methods to JS via window.electronAPI

### Source Code (Sources/MouthType/)

#### Services/ (5,053 LOC - 42% of codebase)
- **ASR Services**: Multiple transcription providers
  - WhisperProvider: Local whisper.cpp integration
  - BailianStreamingProvider: Aliyun Bailian real-time ASR
  - ParaformerProvider: Alibaba Paraformer model
  - SenseVoiceProvider: SenseVoice multilingual ASR
- **AudioManager.swift**: Audio device management and recording
- **VADProcessor.swift**: Voice Activity Detection
- **TextInsertionService.swift**: Cross-app text insertion
- **LogRedaction.swift**: Sensitive data filtering for logs

#### UI/ (2,399 LOC - 20% of codebase)
- **FloatingCapsuleView.swift**: Main dictation interface
- **SettingsView.swift**: Settings UI (SwiftUI)
- **ContentView.swift**: Main window content
- **OnboardingView.swift**: First-time setup wizard

#### Platform/ (1,811 LOC - 15% of codebase)
- **HotkeyMonitor.swift**: Global hotkey registration
- **PermissionManager.swift**: System permission handling
- **ClipboardManager.swift**: Cross-app clipboard operations
- **WindowManager.swift**: Window creation and lifecycle

#### Models/ (715 LOC - 6% of codebase)
- **AppState.swift**: Central app state management (@Observable)
- **AppSettings.swift**: User preferences and configuration
- **TranscriptionRecord.swift**: Data model for transcription history

#### Utilities/ (106 LOC - 1% of codebase)
- Helper functions and extensions

### WebView Bridge (preload.js)

- **448 LOC** - Single JS file serving as WebView-to-native bridge
- Exposes ~100 IPC channels categorized as:
  - API Key management (~20 channels)
  - Streaming ASR (~40 channels)
  - Model management (~15 channels)
  - Window control (~15 channels)
  - Database CRUD (~10 channels)
  - System/clipboard/hotkey (~20 channels)

### Resources/
- ML models (Whisper, Paraformer, SenseVoice) - ~639 MB
- Configuration files
- Assets

### Tests/ (1,458 LOC)
- 6 test files covering:
  - AppSettings (keychain, endpoints, migration)
  - AppState (state transitions, error recovery)
  - AI Providers (availability, endpoint validation)
  - Log Redaction (sensitive data filtering)
  - VAD Processor (configuration, state)
  - Whisper Provider (availability, errors)

## Key Implementation Details

### 1. AppState (@Observable)

Central state management using SwiftUI's @Observable macro:

```swift
@Observable
final class AppState {
    static let shared = AppState()
    
    var dictationState: DictationState = .idle
    var streamingText: String = ""
    private var _audioLevel: Float = 0
    var audioLevel: Float { _audioLevel }
    var lastTranscription: String = ""
    var errorMessage: String = ""
    
    @MainActor
    func setAudioLevel(_ level: Float) { ... }
    
    @MainActor
    func transition(to state: DictationState) { ... }
}
```

### 2. Settings Storage

Settings stored via UserDefaults + Keychain (for sensitive data):

**UserDefaults keys**:
- `bailianEndpoint`: AI endpoint URL
- `selectedASRProvider`: Active transcription provider
- `floatingCapsulePosition`: UI position

**Keychain items** (via `SystemKeychainStore`):
- `bailian_api_key`: Bailian API key
- `ai_api_key`: Generic AI API key
- `openai_api_key`: OpenAI API key

**Security**: API keys never exposed to WebView; all API calls go through native code.

### 3. Audio Pipeline

1. User presses hotkey → AudioManager starts recording
2. Audio buffers collected via AVAudioEngine
3. VADProcessor analyzes voice activity
4. Audio sent to active ASR provider:
   - Local: whisper.cpp process
   - Cloud: Streaming WebSocket or HTTP API
5. Results sent back via callbacks
6. TextInsertionService inserts text into active app

### 4. ASR Providers

**Local (Whisper)**:
- Models stored in `~/Library/Application Support/MouthType/Models/`
- Binary bundled in app resources
- Supports multiple model sizes (tiny → large)

**Cloud (Bailian/Aliyun)**:
- WebSocket streaming for real-time transcription
- HTTP API for non-streaming requests
- Endpoint validation with SSRF protection

### 5. Log Redaction

Sensitive data automatically filtered from logs:
- API keys, passwords, tokens
- Email addresses, phone numbers
- Credit card numbers, bank accounts
- Chinese ID numbers, mobile numbers
- URLs (query parameters stripped)
- File paths (directory hidden)

### 6. Sensitive App Policy

Privacy controls for different application contexts:
- `fullyBlocked`: Password managers (1Password, Keychain, etc.)
- `highPrivacy`: Financial apps (banks, Alipay, PayPal)
- `localOnly`: Security apps (VPN, encryption tools)
- `blockAutoLearn`: Code apps (Terminal, Xcode, VSCode)
- `allowFullPipeline`: General apps (Safari, Notes)

### 7. Build System

**Swift Package Manager**:
- `Package.swift`: Single dependency (SQLite.swift 0.16.0)
- `swift build`: Debug build
- `swift build -c release`: Release build
- `swift test`: Run test suite

**Build Scripts**:
- `scripts/build-app.sh`: Debug build with entitlements
- `scripts/build-with-entitlements.sh`: Release build (⚠️ clears user data)

### 8. Info.plist Configuration

Key settings:
- `LSUIElement`: true (floating app, no Dock icon)
- `NSAppleEventsUsageDescription`: AppleScript permission for text insertion
- `NSMicrophoneUsageDescription`: Audio recording permission

## Development Guidelines

### Adding New Features

1. **New IPC Channel**: Add to preload.js and corresponding Swift handler
2. **New Setting**: Update AppSettings.swift and SettingsView
3. **New UI Component**: Follow SwiftUI patterns in Sources/MouthType/UI/
4. **New Service**: Create in Sources/MouthType/Services/
5. **New Test**: Add to Tests/MouthTypeTests/

### Testing Checklist

- [ ] `swift build` passes with no errors
- [ ] `swift test` passes with all tests green
- [ ] Test both local and cloud ASR modes
- [ ] Verify hotkey works globally
- [ ] Check text insertion in different target apps
- [ ] Test with different audio input devices
- [ ] Verify whisper.cpp model detection
- [ ] Test floating capsule positioning
- [ ] Check settings persistence across restarts

### Common Issues and Solutions

1. **No Audio Detected**:
   - Check microphone permissions in System Settings
   - Verify audio input device selection
   - Check audio levels in debug logs

2. **Transcription Fails**:
   - Ensure whisper.cpp binary is available (check Resources/)
   - Verify model is downloaded
   - Check API key configuration for cloud providers

3. **Text Insertion Not Working**:
   - macOS: Check accessibility permissions (required for AppleScript)
   - Verify target app allows text input
   - Check if app is in blocked list (SensitiveAppPolicy)

4. **Build Issues**:
   - Use `swift build` for development
   - Use `swift build -c release` for production
   - Code signing: `codesign --force --deep --sign - .build/debug/MouthType`

### Platform-Specific Notes

**macOS**:
- Requires accessibility permissions for text insertion (AppleScript)
- Requires microphone permission (prompted by system)
- Floating capsule uses `NSPanel` with `canBecomeKeyWindow`
- System settings accessible via `x-apple.systempreferences:` URL scheme
- Minimum version: macOS 14 (Sonoma)

## Code Style and Conventions

- Use Swift 5.9+ features (async/await, @Observable, etc.)
- Follow existing patterns in Services/ and UI/
- Descriptive error messages for users
- Comprehensive debug logging via os.Logger
- Clean up resources (timers, listeners, subscriptions)
- Handle edge cases gracefully

## Security Considerations

- API keys stored in Keychain, never exposed to WebView
- SSRF protection for endpoint validation
- Log redaction for sensitive data
- Sensitive app policy for privacy control
- No remote code execution
- Sanitized file paths

## Performance Considerations

- Whisper model size vs speed tradeoff
- Audio level update throttling (100ms minimum)
- VAD processing optimization
- Memory usage with large models
- Process timeout protection

## Future Enhancements

- Streaming transcription support
- Custom wake word detection
- Multi-language UI
- Additional cloud providers
- Batch transcription
- Export formats beyond clipboard

---

## Git Commit Guidelines

When writing git commits for this project, follow these requirements:

1. Write Git commits in both Chinese and English. The commit message should have Chinese first, followed by English, separated by a forward slash (/) with spaces around it.

2. Git commit content should be complete and structured, using direct text formatting (e.g., using spaces, line breaks, etc. for line breaks and spacing), do not use Markdown syntax like bullet points, bold, or code blocks.

Example format:

fix: 修复登录页面的样式问题 / Fix login page styling issue

Changes:
- Adjusted button padding on mobile devices
- Fixed color contrast for accessibility
- Updated error message positioning

This ensures commits are readable in plain text format while providing bilingual context for all team members.
