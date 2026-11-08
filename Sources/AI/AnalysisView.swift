import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in row(line) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func row(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            Text(inline(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces))).font(.headline).padding(.top, 6)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(String(line.dropFirst(2))))
            }
            .padding(.leading, raw.hasPrefix(" ") ? 16 : 0)
        } else if line.isEmpty {
            Color.clear.frame(height: 2)
        } else {
            Text(inline(line))
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct AnalysisView: View {
    @ObservedObject var m: AnalysisModel

    private var dateText: String {
        guard let d = m.resultDate else { return "" }
        return L("上次分析：", "Last analysis: ") + d.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("AI 功耗分析", "AI Power Analysis"), systemImage: "sparkles").font(.title3.weight(.semibold))
                Spacer()
                Text(L("已记录 ", "Recorded ") + AnalysisModel.spanText(m.recordedHours)).font(.callout).foregroundStyle(.secondary)
            }
            settings
            HStack(spacing: 10) {
                if m.running {
                    Button(L("取消", "Cancel")) { m.cancel() }
                    ProgressView().controlSize(.small)
                    Text(L("分析中，可能需要一两分钟…", "Analyzing, this can take a minute or two…")).font(.callout).foregroundStyle(.secondary)
                } else {
                    Button(L("开始分析", "Analyze")) { m.analyze() }.keyboardShortcut(.defaultAction)
                }
                Spacer()
                if !m.result.isEmpty { Button(L("复制结果", "Copy")) { m.copyResult() } }
            }
            if let e = m.error { Text(e).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                if m.result.isEmpty {
                    Text(L("让 MenuRunner 记录一段时间（最好一天以上），然后点「开始分析」。AI 会根据各应用的耗电、CPU、GPU、温度、风扇和电池数据给出分析和建议。",
                           "Let MenuRunner record for a while (ideally a day or more), then click Analyze. The AI looks at per-app energy, CPU, GPU, temperature, fan and battery data and suggests improvements."))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownText(text: m.result)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            HStack {
                Text(dateText)
                Spacer()
                Text(L("分析时会把汇总数据发送给所选的 AI 服务", "Summarized data is sent to the selected AI service"))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 560)
    }

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text(L("服务", "Provider"))
                Picker("", selection: $m.provider) {
                    ForEach(AIProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented)
            }
            if m.provider == .openai {
                GridRow {
                    Text("Base URL")
                    TextField(AIClient.defaultOpenAIBase, text: $m.openAIBase).textFieldStyle(.roundedBorder)
                }
            }
            GridRow {
                Text(L("模型", "Model"))
                if m.provider == .anthropic {
                    Picker("", selection: $m.claudeModel) {
                        ForEach(AIClient.claudeModels, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                } else {
                    TextField(L("例如 gpt-4o、deepseek-chat、qwen2.5", "e.g. gpt-4o, deepseek-chat, qwen2.5"), text: $m.openAIModel)
                        .textFieldStyle(.roundedBorder)
                }
            }
            GridRow {
                Text("API Key")
                SecureField(m.provider == .anthropic ? "sk-ant-…" : L("本地模型可留空", "Optional for local models"), text: $m.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { m.saveKey() }
            }
            GridRow {
                Text(L("数据范围", "Range"))
                Picker("", selection: $m.rangeHours) {
                    ForEach(AnalysisModel.ranges, id: \.self) { Text(L("最近 ", "Last ") + AnalysisModel.rangeTitle($0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented)
            }
        }
    }
}
