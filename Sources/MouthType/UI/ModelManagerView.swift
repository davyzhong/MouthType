import os
import SwiftUI

private let modelManagerLog = Logger(subsystem: "com.mouthtype", category: "ModelManagerView")

struct ModelManagerView: View {
    @State private var downloadProgress: [String: Double] = [:]
    @State private var isDownloading = false
    @State private var showingDeleteConfirm = false
    @State private var totalDownloadedSize: String = ""
    @State private var hasInitializedDefault = false

    private let manager = ModelManager.shared
    private let settings = AppSettings.shared

    private var currentProviderDisplayName: String {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.currentProviderDisplayName
        }
        return settings.asrProvider.displayName
    }

    private var currentModelName: String {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.currentModelName
        }
        switch settings.asrProvider {
        case .localWhisper:
            return "Whisper \(settings.whisperModel.capitalized)"
        case .localParaformer:
            return "Paraformer INT8 (中文最佳)"
        case .bailianStreaming, .bailian:
            return "百炼云端"
        }
    }

    private var currentModelPath: String {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.currentModelPath
        }
        switch settings.asrProvider {
        case .localWhisper:
            return settings.whisperModelURL.deletingLastPathComponent().path
        case .localParaformer:
            return settings.paraformerModelURL.deletingLastPathComponent().path
        case .bailianStreaming, .bailian:
            return "-"
        }
    }

    private var currentDownloadedSizeText: String {
        if UITestConfiguration.current.isEnabled {
            return UITestConfiguration.current.currentModelSizeText
        }
        switch settings.asrProvider {
        case .localWhisper:
            return formattedSize(of: settings.whisperModelURL)
        case .localParaformer:
            let modelSize = fileSize(of: settings.paraformerModelURL)
            let tokensSize = fileSize(of: settings.paraformerModelURL.deletingLastPathComponent().appendingPathComponent("tokens.txt"))
            return formatSize(modelSize + tokensSize)
        case .bailianStreaming, .bailian:
            return "-"
        }
    }

    var body: some View {
        Form {
            Section("Whisper 模型") {
                ForEach(manager.availableWhisperModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(model.name)
                                    .font(.system(size: 13, weight: .medium))
                                if model.filename.contains("small") || model.filename.contains("medium") {
                                    Text("中文推荐")
                                        .font(.caption)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(3)
                                }
                            }
                            Text(model.sizeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        let modelId = model.filename.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "")
                        let isDownloaded = isWhisperModelAvailable(model)
                        let isActive = settings.asrProvider == .localWhisper && settings.whisperModel == modelId

                        if let progress = downloadProgress[model.filename] {
                            ProgressView(value: progress)
                                .frame(width: 80)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                                .accessibilityIdentifier("settings.models.downloadProgress.\(model.filename)")
                        } else if isDownloaded {
                            if isActive {
                                Label("使用中", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                HStack(spacing: 8) {
                                    Button("切换") {
                                        switchToModel(model)
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                                    Button("删除") {
                                        try? manager.deleteWhisperModel(model)
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                                    .foregroundStyle(.red)
                                }
                            }
                        } else {
                            Button("下载") {
                                downloadModel(model)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(isDownloading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Paraformer 模型") {
                ForEach(manager.availableParaformerModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(model.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text("中文最佳")
                                    .font(.caption)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(3)
                            }
                            Text(model.sizeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        let isDownloaded = isParaformerModelAvailable(model)
                        let isActive = settings.asrProvider == .localParaformer && settings.paraformerModel == model.filename

                        if let progress = downloadProgress[model.filename] {
                            ProgressView(value: progress)
                                .frame(width: 80)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                                .accessibilityIdentifier("settings.models.downloadProgress.\(model.filename)")
                        } else if UITestConfiguration.current.isModelDownloaded {
                            HStack(spacing: 8) {
                                Button("切换") {
                                    switchToParaformerModel(model)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                Button("删除") {
                                    try? manager.deleteParaformerModel(model)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .foregroundStyle(.red)
                            }
                        } else if isDownloaded {
                            if isActive {
                                Label("使用中", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                HStack(spacing: 8) {
                                    Button("切换") {
                                        switchToParaformerModel(model)
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                                    Button("删除") {
                                        try? manager.deleteParaformerModel(model)
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                                    .foregroundStyle(.red)
                                }
                            }
                        } else {
                            Button("下载") {
                                downloadParaformerModel(model)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(isDownloading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("当前配置") {
                HStack {
                    Text("当前 ASR 引擎")
                    Spacer()
                    Text(currentProviderDisplayName)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("settings.models.currentProviderValue")
                        .accessibilityLabel(currentProviderDisplayName)
                }
                HStack {
                    Text("当前模型")
                    Spacer()
                    Text(currentModelName)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("settings.models.currentModelValue")
                        .accessibilityLabel(currentModelName)
                }
                HStack {
                    Text("模型路径")
                    Spacer()
                    Text(currentModelPath)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("settings.models.currentModelPathValue")
                        .accessibilityLabel(currentModelPath)
                }
                HStack {
                    Text("已下载模型大小")
                    Spacer()
                    Text(currentDownloadedSizeText)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("settings.models.currentDownloadedSizeValue")
                        .accessibilityLabel(currentDownloadedSizeText)
                }
            }

            Section("清理") {
                Button("删除所有下载的模型", role: .destructive) {
                    showingDeleteConfirm = true
                }
                .accessibilityIdentifier("settings.models.deleteAllButton")
            }
        }
        .onAppear {
            if UITestConfiguration.current.isEnabled,
               UITestConfiguration.current.isModelDownloading,
               let progress = UITestConfiguration.current.modelDownloadProgress {
                isDownloading = true
                downloadProgress[settings.paraformerModel] = progress
            }
            calculateDownloadedSize()
        }
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
                .accessibilityIdentifier("settings.models.deleteConfirm.cancelButton")
            Button("删除全部", role: .destructive) {
                deleteAllModels()
            }
            .accessibilityIdentifier("settings.models.deleteConfirm.deleteButton")
        } message: {
            Text("这将删除所有已下载的本地模型。需要重新下载才能使用。")
        }
    }

    private func switchToModel(_ model: ModelManager.WhisperModel) {
        let modelId = model.filename.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "")
        settings.asrProvider = .localWhisper
        settings.whisperModel = modelId
    }

    private func switchToParaformerModel(_ model: ModelManager.ParaformerModel) {
        let modelId = model.filename
        settings.asrProvider = .localParaformer
        settings.paraformerModel = modelId
    }

    private func isWhisperModelAvailable(_ model: ModelManager.WhisperModel) -> Bool {
        let userURL = manager.whisperModelURL(for: model)
        if FileManager.default.fileExists(atPath: userURL.path) {
            return true
        }
        let modelId = model.filename.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "")
        let bundledURL = Bundle.main.url(forResource: "whisper-models/ggml-\(modelId)", withExtension: "bin")
        return bundledURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private func isParaformerModelAvailable(_ model: ModelManager.ParaformerModel) -> Bool {
        let userURL = manager.paraformerModelURL(for: model)
        if FileManager.default.fileExists(atPath: userURL.path) {
            return true
        }
        let bundledURL = Bundle.main.url(forResource: "paraformer-models/\(model.filename)", withExtension: "onnx")
        return bundledURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private func calculateDownloadedSize() {
        var totalSize: Int64 = 0
        let fm = FileManager.default
        let whisperDir = settings.modelsDirectory.appendingPathComponent("whisper")

        if let files = try? fm.contentsOfDirectory(at: whisperDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files where file.pathExtension == "bin" {
                totalSize += fileSize(of: file)
            }
        }

        totalDownloadedSize = formatSize(totalSize)
    }

    private func fileSize(of url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    private func formattedSize(of url: URL) -> String {
        formatSize(fileSize(of: url))
    }

    private func formatSize(_ totalSize: Int64) -> String {
        if totalSize > 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", Double(totalSize) / Double(1024 * 1024 * 1024))
        } else if totalSize > 1024 * 1024 {
            return String(format: "%.1f MB", Double(totalSize) / Double(1024 * 1024))
        } else {
            return "\(totalSize / 1024) KB"
        }
    }

    private func deleteAllModels() {
        let whisperDir = settings.modelsDirectory.appendingPathComponent("whisper")
        try? FileManager.default.removeItem(at: whisperDir)
        calculateDownloadedSize()
    }

    private func downloadModel(_ model: ModelManager.WhisperModel) {
        isDownloading = true
        downloadProgress[model.filename] = 0

        Task {
            do {
                try await manager.download(model: model) { progress in
                    downloadProgress[model.filename] = progress
                }
                downloadProgress.removeValue(forKey: model.filename)
                calculateDownloadedSize()
            } catch {
                downloadProgress.removeValue(forKey: model.filename)
                modelManagerLog.error("Download failed: \(error)")
            }
            isDownloading = false
        }
    }

    private func downloadParaformerModel(_ model: ModelManager.ParaformerModel) {
        isDownloading = true
        downloadProgress[model.filename] = 0

        Task {
            do {
                try await manager.download(model: model) { progress in
                    downloadProgress[model.filename] = progress
                }
                downloadProgress.removeValue(forKey: model.filename)
                calculateDownloadedSize()
            } catch {
                downloadProgress.removeValue(forKey: model.filename)
                modelManagerLog.error("Download failed: \(error)")
            }
            isDownloading = false
        }
    }
}
