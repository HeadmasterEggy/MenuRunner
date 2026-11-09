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
                Text(L("能效分", "Score")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 86, height: 86)
    }
}

struct AnalysisResultView: View {
    let result: AnalysisResult
    let shares: [EnergyShare]

    private func path(for name: String) -> String? { shares.first { $0.name == name }?.path }

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
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Circle().fill(s.impact.color))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(s.title).font(.callout.weight(.semibold)); LevelBadge(text: s.impact.impactText, color: s.impact.color) }
                                Text(s.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            if !result.findings.isEmpty {
                ChartCard(title: L("发现", "Findings"), icon: "magnifyingglass") {
                    ForEach(result.findings) { f in
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
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(nsImage: ProcessMemory.icon(path(for: a.name))).resizable().frame(width: 16, height: 16).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                            Text(a.name).font(.callout.weight(.medium)).frame(width: 130, alignment: .leading).lineLimit(1)
                            LevelBadge(text: a.verdict.text, color: a.verdict.color)
                            Text(a.note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}
