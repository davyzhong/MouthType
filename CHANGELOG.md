# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 自动化 CI/CD 工作流 / Automated CI/CD workflows
- GitHub Actions release pipeline
- SwiftLint and swift-format configuration
- Performance benchmark tests
- Code coverage reporting

### Changed
- preload.js 模块化拆分 / Modularized preload.js into 6 sub-modules
- 统一构建脚本 / Unified build script (scripts/build.sh)
- API Key 安全加固 / API Key security hardening (main-process proxy)

### Fixed
- 测试套件编译修复 / Fixed test suite compilation (106 → 149 tests)
- Info.plist LSUIElement 设置 / Fixed LSUIElement to hide from Dock
- CLAUDE.md 重写为 Swift 架构 / Rewrote CLAUDE.md for Swift architecture

## [0.1.0] - 2024-XX-XX

### Added
- Initial release of MouthType
- Local whisper.cpp integration
- Cloud ASR via Bailian/Aliyun
- Floating capsule UI
- WebKit settings panel
- Global hotkey support
- Text insertion via AppleScript
- Transcription history with SQLite
- Custom dictionary and auto-learn
- Sensitive app policy for privacy

[Unreleased]: https://github.com/davyzhong/mouthtype/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/davyzhong/mouthtype/releases/tag/v0.1.0
