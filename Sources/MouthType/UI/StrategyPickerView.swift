import SwiftUI

/// 策略选择器视图
///
/// 让用户选择后处理策略和输入场景
struct StrategyPickerView: View {
    @AppStorage("postProcessStrategy") private var strategyRawValue: String = PostProcessStrategy.lightPolish.rawValue
    @AppStorage("inputContextStrategy") private var contextRawValue: String = InputContextStrategy.chat.rawValue
    @AppStorage("aiEnabled") private var aiEnabled: Bool = true
    @AppStorage("aiAutoIterate") private var aiAutoIterate: Bool = false
    @AppStorage("aiIterations") private var aiIterations: Int = 1

    private var selectedStrategy: PostProcessStrategy {
        PostProcessStrategy(rawValue: strategyRawValue) ?? .lightPolish
    }

    private var selectedContext: InputContextStrategy {
        InputContextStrategy(rawValue: contextRawValue) ?? .chat
    }

    var body: some View {
        Form {
            // AI 开关
            Section("AI 后处理") {
                Toggle("启用 AI 后处理", isOn: $aiEnabled)
            }

            if aiEnabled {
                // 输出策略
                Section("输出策略") {
                    Picker("策略", selection: $strategyRawValue) {
                        ForEach(PostProcessStrategy.allCases, id: \.rawValue) { strategy in
                            VStack(alignment: .leading) {
                                Text(strategy.displayName)
                                Text(strategy.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(strategy.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    // 策略详情
                    StrategyDetailCard(strategy: selectedStrategy)
                }

                // 输入场景
                Section("输入场景") {
                    Picker("场景", selection: $contextRawValue) {
                        ForEach(InputContextStrategy.allCases, id: \.rawValue) { context in
                            Text(context.displayName).tag(context.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    // 场景推荐策略
                    HStack {
                        Text("推荐策略:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedContext.recommendedOutputStrategy.displayName)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // 迭代设置
                Section("迭代优化") {
                    Toggle("自动多轮迭代", isOn: $aiAutoIterate)

                    if aiAutoIterate {
                        Stepper("迭代次数：\(aiIterations)", value: $aiIterations, in: 1...3)
                    }
                }
            }

            // 术语管理
            Section("术语管理") {
                NavigationLink("管理术语和热词") {
                    TerminologyManagementView()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 策略详情卡片
struct StrategyDetailCard: View {
    let strategy: PostProcessStrategy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: strategyIcon)
                    .foregroundStyle(.blue)
                Text("当前策略")
                    .font(.headline)
            }

            Text(strategy.description)
                .font(.subheadline)

            HStack(spacing: 16) {
                DetailBadge(label: "迭代次数", value: "\(strategy.recommendedIterations)")
                DetailBadge(label: "AI 模式", value: strategy.aiMode == .cleanup ? "清理" : "重写")
            }
        }
        .padding()
        .background(.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var strategyIcon: String {
        switch strategy {
        case .rawFirst: "text.badge.checkmark"
        case .lightPolish: "sparkles"
        case .publishable: "document.fill"
        case .structuredRewrite: "text.alignjustify"
        }
    }
}

/// 详情徽章
struct DetailBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.2))
        .cornerRadius(4)
    }
}

/// 术语管理视图
struct TerminologyManagementView: View {
    @StateObject private var service = TerminologyService.shared
    @State private var newTerm = ""
    @State private var newHotword = ""
    @State private var showingAddTerm = false
    @State private var showingAddHotword = false

    var body: some View {
        Form {
            Section("已学习术语") {
                if service.getAllHotwords().isEmpty {
                    Text("暂无术语")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.getAllHotwords(), id: \.self) { term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button("删除", role: .destructive) {
                                service.removeTerm(term)
                            }
                        }
                    }
                }

                Button("添加术语") {
                    showingAddTerm = true
                }
            }

            Section("使用说明") {
                Text("术语会影响 ASR 识别优先级，添加后识别准确率会提升")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddTerm) {
            AddTermSheet(newTerm: $newTerm, service: service)
        }
    }
}

/// 添加术语表单
struct AddTermSheet: View {
    @Binding var newTerm: String
    @ObservedObject var service: TerminologyService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                PasteableTextField(placeholder: "术语（如产品名、技术词）", text: $newTerm)
            }
            .formStyle(.grouped)
            .navigationTitle("添加术语")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        service.addTerm(newTerm)
                        newTerm = ""
                        dismiss()
                    }
                    .disabled(newTerm.isEmpty)
                }
            }
        }
    }
}

#Preview {
    StrategyPickerView()
}
