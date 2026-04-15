import SwiftUI

struct HistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var searchText = ""
    @State private var selectedEntries: Set<HistoryEntry.ID> = []
    @State private var showingExportSheet = false
    @State private var exportText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                PasteableTextField(placeholder: "搜索历史记录…", text: $searchText)
                    .accessibilityIdentifier("settings.history.searchField")
                    .onSubmit { loadEntries() }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        loadEntries()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button("搜索") { loadEntries() }
                    .controlSize(.small)
                    .accessibilityIdentifier("settings.history.searchButton")
            }
            .padding(8)
            .background(.bar)

            Divider()

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("暂无转写记录")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.history.emptyState")
            } else {
                List(selection: $selectedEntries) {
                    ForEach(entries) { entry in
                        HistoryRow(entry: entry)
                            .contextMenu {
                                Button("复制原文") {
                                    copyToClipboard(entry.text)
                                }
                                if let processed = entry.processedText {
                                    Button("复制处理后文本") {
                                        copyToClipboard(processed)
                                    }
                                }
                                Button("删除", role: .destructive) {
                                    deleteEntry(entry)
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Bottom bar
            HStack {
                Text("\(entries.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("settings.history.countLabel")
                    .accessibilityLabel("\(entries.count) 条记录")
                Spacer()
                if !entries.isEmpty {
                    if !selectedEntries.isEmpty {
                        Button("删除选中 (\(selectedEntries.count))") {
                            deleteSelected()
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                    Button("导出全部") {
                        exportText = HistoryStore.shared.exportAll()
                        showingExportSheet = true
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("settings.history.exportAllButton")
                    Button("清空全部") {
                        clearAll()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }
            }
            .padding(8)
            .background(.bar)
        }
        .onAppear {
            searchText = UITestConfiguration.current.historySearchKeyword
            loadEntries()
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportSheetView(text: exportText)
        }
    }

    private func loadEntries() {
        if searchText.isEmpty {
            entries = HistoryStore.shared.recent()
        } else {
            entries = HistoryStore.shared.search(keyword: searchText)
        }
        selectedEntries = []
    }

    private func deleteEntry(_ entry: HistoryEntry) {
        HistoryStore.shared.delete(entryId: entry.id)
        loadEntries()
    }

    private func deleteSelected() {
        for id in selectedEntries {
            HistoryStore.shared.delete(entryId: id)
        }
        loadEntries()
    }

    private func clearAll() {
        HistoryStore.shared.deleteAll()
        entries = []
        selectedEntries = []
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ExportSheetView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("导出历史记录")
                .font(.headline)
                .padding()

            Divider()

            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(minWidth: 400, minHeight: 300)
                .accessibilityIdentifier("settings.history.exportText")

            Divider()

            HStack {
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .accessibilityIdentifier("settings.history.exportCopyButton")
                Button("完成") {
                    dismiss()
                }
                .accessibilityIdentifier("settings.history.exportDoneButton")
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.history.exportSheet")
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.timestamp, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(2)
                .font(.system(size: 13))
                .accessibilityIdentifier("settings.history.row.\(entry.id).rawText")
                .accessibilityLabel(entry.text)
            if let processed = entry.processedText, processed != entry.text {
                Text(processed)
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.history.row.\(entry.id).processedText")
                    .accessibilityLabel(processed)
            }
            HStack {
                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if entry.processedText != nil {
                    Text("AI")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15))
                        .cornerRadius(3)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
