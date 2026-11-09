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

    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
                .padding(16)
                .glassCard()
            if let e = m.error { Text(e).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                GlassEffectContainer(spacing: GlassMetrics.spacing) {
                    VStack(alignment: .leading, spacing: GlassMetrics.spacing) {
                        if let r = m.parsed { AnalysisSummary(result: r, m: m) }
                        dataSection
                        aiSection
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            HStack {
                Text(dateText)
                Spacer()
                Text(L("分析时会把汇总数据发送给所选的 AI 服务", "Summarized data is sent to the selected AI service"))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 8)
        .frame(minWidth: 640, minHeight: 640)
        .background(WindowGlassBackground().ignoresSafeArea())
        .onAppear { showSettings = (m.apiKey.isEmpty && m.provider == .anthropic) || m.model.isEmpty }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("AI 系统分析", "AI System Analysis"), systemImage: "sparkles").font(.title3.weight(.semibold))
                Spacer()
                Text(L("已记录 ", "Recorded ") + AnalysisModel.spanText(m.recordedHours)).font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $showSettings) { settings.padding(.top, 8) } label: {
                Text(L("AI 服务：", "AI service: ") + m.provider.title + (m.model.isEmpty ? "" : " · " + m.model)).font(.callout)
            }
            HStack(spacing: 10) {
                Picker("", selection: $m.rangeHours) {
                    ForEach(AnalysisModel.ranges, id: \.self) { Text(L("最近 ", "Last ") + AnalysisModel.rangeTitle($0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                Spacer()
                if m.running {
                    ProgressView().controlSize(.small)
                    Text(L("分析中…", "Analyzing…")).font(.callout).foregroundStyle(.secondary)
                    Button(L("取消", "Cancel")) { m.cancel() }.buttonStyle(.glass)
                } else {
                    if !m.result.isEmpty { Button(L("复制", "Copy"), systemImage: "doc.on.doc") { m.copyResult() }.buttonStyle(.glass) }
                    Button(L("开始 AI 分析", "Run AI Analysis"), systemImage: "sparkles") { m.analyze() }
                        .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var stepText: String {
        let minutes = Int(PowerStats.step(hours: m.rangeHours) / 60)
        return minutes < 60 ? L("每 \(minutes) 分钟", "per \(minutes) min") : L("每 \(minutes / 60) 小时", "per \(minutes / 60) h")
    }

    @ViewBuilder private var dataSection: some View {
        if m.buckets.isEmpty {
            ChartCard(title: L("数据", "Data"), icon: "chart.bar") {
                Text(L("还没有记录到数据。MenuRunner 每 5 分钟存一次，过一会儿再来看。", "Nothing recorded yet. MenuRunner saves every 5 minutes; check back soon."))
                    .foregroundStyle(.secondary)
            }
        } else {
            MetricTiles(m: m)
            ChartCard(title: m.metric.title + L("趋势（", " trend (") + stepText + L("）", ")"), icon: "chart.xyaxis.line") {
                if let app = m.selectedApp {
                    Button { withAnimation(.snappy) { m.selectedApp = nil } } label: {
                        Label(app, systemImage: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.glass).controlSize(.small).tint(ChartPalette.app)
                }
            } content: {
                if m.trend.count >= 2 { TrendChart(m: m) } else {
                    Text(L("数据点太少，多记录一会儿再看趋势。", "Not enough points yet for a trend.")).foregroundStyle(.secondary)
                }
                if m.selectedApp != nil && !(m.metric == .power || m.metric == .cpu || m.metric == .memory) {
                    Text(L("这个指标没有按应用的数据，切到功耗、CPU 或内存可以看所选应用的曲线。", "This metric has no per-app data; switch to Power, CPU or Memory to see the selected app."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ChartCard(title: L("应用排行", "Top apps"), icon: "chart.pie.fill") {
                Picker("", selection: $m.rankKind) {
                    ForEach(RankKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            } content: {
                RankingChart(m: m)
            }
            if m.daily.count >= 2 {
                ChartCard(title: L("每天耗电", "Energy per day"), icon: "chart.bar.fill") { DailyEnergyChart(days: m.daily) }
            }
        }
    }

    @ViewBuilder private var aiSection: some View {
        if let r = m.parsed {
            AnalysisDetails(result: r, m: m)
        } else if !m.result.isEmpty {
            ChartCard(title: L("AI 分析", "AI analysis"), icon: "sparkles") { MarkdownText(text: m.result) }
        } else {
            ChartCard(title: L("AI 分析", "AI analysis"), icon: "sparkles") {
                Text(L("让 MenuRunner 记录一段时间（最好一天以上），然后点「开始 AI 分析」。AI 会给出能效评分、发现的问题，以及按影响排序的建议。",
                       "Let MenuRunner record for a while (ideally a day or more), then click Run AI Analysis to get an efficiency score, findings and suggestions ranked by impact."))
                    .foregroundStyle(.secondary)
            }
        }
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
        }
    }
}
