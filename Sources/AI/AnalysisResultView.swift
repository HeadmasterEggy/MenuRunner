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
    var bars: Int { self == .high ? 3 : (self == .medium ? 2 : 1) }
    var impactText: String { self == .high ? L("影响大", "High impact") : (self == .medium ? L("影响中", "Medium impact") : L("影响小", "Low impact")) }
}

extension Verdict {
    var color: Color { self == .expected ? .green : (self == .watch ? .orange : .red) }
    var text: String { self == .expected ? L("正常", "Expected") : (self == .watch ? L("留意", "Watch") : L("异常", "Abnormal")) }
    var icon: String { self == .expected ? "checkmark.circle.fill" : (self == .watch ? "exclamationmark.circle.fill" : "xmark.octagon.fill") }
}

enum ScoreColor {
    static func of(_ score: Int) -> Color { score >= 80 ? .green : (score >= 60 ? .yellow : (score >= 40 ? .orange : .red)) }
}

struct ScoreRing: View {
    let score: Int
    private var color: Color { ScoreColor.of(score) }

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

    static func icon(_ c: String) -> String {
        switch c {
        case "power": return "bolt.fill"
        case "cpu": return "cpu"
        case "gpu": return "cpu.fill"
        case "memory": return "memorychip"
        case "thermal": return "thermometer.medium"
        case "battery": return "battery.75percent"
        case "network": return "network"
        default: return "circle"
        }
    }
}

struct AnalysisSummary: View {
    let result: AnalysisResult
    @ObservedObject var m: AnalysisModel

    private func count(_ c: String) -> [Level] { result.findings.filter { $0.category == c }.map(\.severity) }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ScoreRing(score: result.score)
            VStack(alignment: .leading, spacing: 10) {
                Text(result.headline).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !result.orderedScores.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 6) {
                        ForEach(result.orderedScores, id: \.0) { c, score in bar(c, score: score) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: ScoreColor.of(result.score).opacity(0.12))
    }

    private func bar(_ c: String, score: Int) -> some View {
        let selected = m.category == c
        let levels = count(c)
        return Button { withAnimation(.snappy) { m.toggle(category: c) } } label: {
            HStack(spacing: 6) {
                Image(systemName: FindingCategory.icon(c)).font(.caption).frame(width: 14)
                Text(FindingCategory.title(c)).font(.caption).frame(width: Lang.isZh ? 34 : 58, alignment: .leading).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(ScoreColor.of(score)).frame(width: g.size.width * CGFloat(score) / 100)
                    }
                }
                .frame(height: 6)
                Text("\(score)").font(.caption.monospacedDigit()).frame(width: 24, alignment: .trailing)
                HStack(spacing: 2) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { _, l in Circle().fill(l.color).frame(width: 5, height: 5) }
                }
                .frame(width: 22, alignment: .leading)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.2) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("点击查看这一类的图表和发现", "Click to see this category's chart and findings"))
    }
}

struct AnalysisDetails: View {
    let result: AnalysisResult
    @ObservedObject var m: AnalysisModel
    @State private var expanded: Set<String> = []

    private var findings: [(Int, Finding)] {
        result.findings.enumerated().map { ($0 + 1, $1) }.filter { m.category == nil || $0.1.category == m.category }
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private func timeText(_ r: ClosedRange<Date>) -> String {
        let a = Self.timeFormat.string(from: r.lowerBound)
        guard r.upperBound > r.lowerBound else { return a }
        let sameDay = Calendar.current.isDate(r.lowerBound, inSameDayAs: r.upperBound)
        return a + "–" + (sameDay ? r.upperBound.formatted(date: .omitted, time: .shortened) : Self.timeFormat.string(from: r.upperBound))
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if !result.findings.isEmpty { findingsCard }
            if !result.suggestions.isEmpty { suggestionsCard }
        }
    }

    private var findingsCard: some View {
        ChartCard(title: L("发现", "Findings") + (m.category.map { " · " + FindingCategory.title($0) } ?? ""), icon: "magnifyingglass") {
            if m.category != nil {
                Button { withAnimation(.snappy) { m.category = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        } content: {
            ForEach(findings, id: \.1.id) { n, f in
                let focused = m.focusFinding == f.id
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(n)").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(Circle().fill(f.severity.color))
                        if let c = f.category { Image(systemName: FindingCategory.icon(c)).font(.caption).foregroundStyle(.secondary) }
                        Text(f.title).font(.callout.weight(.medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if let r = f.range { Text(timeText(r)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    if focused {
                        Text(f.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 22)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(focused ? f.severity.color.opacity(0.15) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { m.toggle(finding: f) } }
                .help(f.detail)
            }
        }
    }

    private var suggestionsCard: some View {
        ChartCard(title: L("建议", "Suggestions"), icon: "lightbulb.fill") {
            ForEach(result.suggestions) { s in
                let open = expanded.contains(s.id)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1).fill(i < s.impact.bars ? s.impact.color : Color.primary.opacity(0.12)).frame(width: 4, height: 12)
                            }
                        }
                        Text(s.title).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    if open {
                        Text(s.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 20)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { toggle(s.id) }
                .help(s.impact.impactText + "：" + s.detail)
            }
        }
    }
}
