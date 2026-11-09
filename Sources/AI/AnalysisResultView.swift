import SwiftUI

struct LevelBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

extension Level {
    var color: Color { self == .high ? .red : (self == .medium ? .orange : .green) }
    var severityText: String { self == .high ? L("严重", "High") : (self == .medium ? L("注意", "Medium") : L("轻微", "Low")) }
    var impactText: String { self == .high ? L("影响大", "High impact") : (self == .medium ? L("影响中", "Medium impact") : L("影响小", "Low impact")) }
}

extension Verdict {
    var color: Color { self == .expected ? .green : (self == .watch ? .orange : .red) }
    var text: String { self == .expected ? L("正常", "Expected") : (self == .watch ? L("留意", "Watch") : L("异常", "Abnormal")) }
}

struct ScoreRing: View {
    let score: Int
    private var color: Color { score >= 80 ? .green : (score >= 60 ? .yellow : (score >= 40 ? .orange : .red)) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 9)
            Circle().trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.title.weight(.bold).monospacedDigit())
                Text(L("健康分", "Score")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 86, height: 86)
    }
}

enum FindingCategory {
    static func title(_ c: String) -> String {
        switch c {
        case "power": return L("功耗", "Power")
        case "cpu": return "CPU"
        case "gpu": return "GPU"
        case "memory": return L("内存", "Memory")
        case "thermal": return L("温度", "Thermal")
        case "battery": return L("电池", "Battery")
        case "network": return L("网络", "Network")
        default: return c
        }
    }

    static func metric(_ c: String) -> Metric? {
        switch c {
        case "power": return .power
        case "cpu": return .cpu
        case "gpu": return .gpu
        case "memory": return .memory
        case "thermal": return .socTemp
        case "battery": return .battery
        case "network": return .netDown
        default: return nil
        }
    }
}

struct AnalysisResultView: View {
    let result: AnalysisResult
    @ObservedObject var m: AnalysisModel
    @State private var category: String?
    @State private var expanded: Set<String> = []

    private func path(for name: String) -> String? {
        m.buckets.lazy.flatMap(\.apps).first { $0.name == name }?.path
    }

    private var categories: [String] {
        var seen = Set<String>()
        return result.findings.compactMap(\.category).filter { seen.insert($0).inserted }
    }

    private var visibleFindings: [Finding] {
        result.findings.filter { category == nil || $0.category == category }.sorted { $0.severity < $1.severity }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ScoreRing(score: result.score)
                Text(result.headline).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            if !result.suggestions.isEmpty {
                ChartCard(title: L("建议（按影响排序）", "Suggestions (by impact)"), icon: "lightbulb.fill") {
                    ForEach(Array(result.suggestions.enumerated()), id: \.element.id) { i, s in
                        let open = expanded.contains(s.id)
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Circle().fill(s.impact.color))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(s.title).font(.callout.weight(.semibold))
                                    LevelBadge(text: s.impact.impactText, color: s.impact.color)
                                    Spacer()
                                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.tertiary)
                                }
                                Text(s.detail).font(.callout).foregroundStyle(.secondary)
                                    .lineLimit(open ? nil : 1).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { if open { expanded.remove(s.id) } else { expanded.insert(s.id) } } }
                    }
                }
            }
            if !result.findings.isEmpty {
                ChartCard(title: L("发现", "Findings"), icon: "magnifyingglass") {
                    if categories.count > 1 {
                        HStack(spacing: 6) {
                            chip(L("全部", "All"), selected: category == nil) { withAnimation(.snappy) { category = nil } }
                            ForEach(categories, id: \.self) { c in
                                chip(FindingCategory.title(c), selected: category == c) {
                                    withAnimation(.snappy) {
                                        category = category == c ? nil : c
                                        if let metric = FindingCategory.metric(c), m.availableMetrics.contains(metric) { m.metric = metric }
                                    }
                                }
                            }
                        }
                    }
                    ForEach(visibleFindings) { f in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(f.severity.color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(f.title).font(.callout.weight(.semibold)); LevelBadge(text: f.severity.severityText, color: f.severity.color) }
                                Text(f.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !result.apps.isEmpty {
                ChartCard(title: L("应用点评", "Apps"), icon: "app.badge") {
                    ForEach(result.apps) { a in
                        let selected = m.selectedApp == a.name
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(nsImage: ProcessMemory.icon(path(for: a.name))).resizable().frame(width: 16, height: 16).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                            Text(a.name).font(.callout.weight(.medium)).frame(width: 130, alignment: .leading).lineLimit(1)
                            LevelBadge(text: a.verdict.text, color: a.verdict.color)
                            Text(a.note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? ChartPalette.app.opacity(0.15) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { m.toggle(app: a.name) } }
                        .help(L("点击在趋势图里查看这个应用", "Click to show this app in the trend chart"))
                    }
                }
            }
        }
    }
}
