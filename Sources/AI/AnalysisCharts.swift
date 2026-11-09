import SwiftUI
import Charts

enum ChartPalette {
    static let apps: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .indigo, .mint]
    static let other = Color.gray.opacity(0.6)
    static let accent = Color.yellow
    static let app = Color.pink

    static func color(_ share: EnergyShare, at index: Int) -> Color {
        share.name == PowerStats.otherName ? other : apps[index % apps.count]
    }

    static func label(_ share: EnergyShare) -> String {
        share.name == PowerStats.otherName ? L("其他", "Other") : share.name
    }
}

struct ChartCard<Content: View, Accessory: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

extension ChartCard where Accessory == EmptyView {
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: icon, accessory: { EmptyView() }, content: content)
    }
}

struct MetricTiles: View {
    @ObservedObject var m: AnalysisModel
    var columns = 6

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(m.availableMetrics) { metric in tile(metric) }
        }
    }

    private func tile(_ metric: Metric) -> some View {
        let selected = m.metric == metric
        let points = PowerStats.trend(m.buckets, metric: metric, step: m.step, app: nil, cores: m.cores)
        return Button { withAnimation(.snappy) { m.metric = metric } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(metric.title, systemImage: metric.icon).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(PowerStats.average(m.buckets, metric: metric).map(metric.format) ?? "--")
                    .font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                Sparkline(points: points, color: selected ? Color.accentColor : ChartPalette.accent)
                    .frame(height: 18)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(radius: GlassMetrics.tileRadius, tint: selected ? Color.accentColor.opacity(0.16) : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .help(metric.usesMax ? L("最高值", "Peak") : L("平均值", "Average"))
    }
}

struct Sparkline: View {
    let points: [TrendPoint]
    let color: Color

    var body: some View {
        if points.count >= 2 {
            Chart(points) { p in
                AreaMark(x: .value("Time", p.time), y: .value("Value", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        } else {
            Color.clear
        }
    }
}

struct TrendChart: View {
    @ObservedObject var m: AnalysisModel
    @State private var hover: Date?

    private var points: [TrendPoint] { m.trend }
    private var showsApp: Bool { m.selectedApp != nil && points.contains { $0.appValue != nil } }

    private func nearest(_ d: Date) -> TrendPoint? {
        points.min { abs($0.time.timeIntervalSince(d)) < abs($1.time.timeIntervalSince(d)) }
    }

    private var step: TimeInterval { m.step }

    private func band(_ r: ClosedRange<Date>) -> ClosedRange<Date> {
        let start = r.lowerBound
        let end = max(r.upperBound, start.addingTimeInterval(step))
        guard let first = points.first?.time, let last = points.last?.time, first < last else { return start...end }
        let hi = min(max(end, first), last)
        let lo = min(max(start, first), max(hi.addingTimeInterval(-step), first))
        return lo...hi
    }

    private func hits(_ d: Date) -> [(Int, Finding)] {
        m.chartFindings.filter { band($0.2).contains(d) }.map { ($0.0, $0.1) }
    }

    var body: some View {
        let selected = hover.flatMap(nearest)
        Chart {
            ForEach(m.chartFindings, id: \.1.id) { n, f, range in
                let b = band(range)
                RectangleMark(xStart: .value("Start", b.lowerBound), xEnd: .value("End", b.upperBound))
                    .foregroundStyle(f.severity.color.opacity(m.focusFinding == f.id ? 0.3 : (m.focusFinding == nil ? 0.14 : 0.06)))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("\(n)").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(Circle().fill(f.severity.color))
                    }
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.time), y: .value("Value", p.value), series: .value("Series", "system"))
                    .foregroundStyle(LinearGradient(colors: [ChartPalette.accent.opacity(0.4), ChartPalette.accent.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("Value", p.value), series: .value("Series", "system"))
                    .foregroundStyle(ChartPalette.accent)
                    .interpolationMethod(.monotone)
            }
            if showsApp {
                ForEach(points) { p in
                    if let a = p.appValue {
                        LineMark(x: .value("Time", p.time), y: .value("Value", a), series: .value("Series", "app"))
                            .foregroundStyle(ChartPalette.app)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            if let s = selected {
                RuleMark(x: .value("Time", s.time))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .center, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        tooltip(s)
                    }
                PointMark(x: .value("Time", s.time), y: .value("Value", s.value)).foregroundStyle(ChartPalette.accent).symbolSize(50)
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(m.metric == .pressure ? String(format: "%.0f", d) : m.metric.format(d)) } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            guard let plot = proxy.plotFrame else { return }
                            hover = proxy.value(atX: p.x - geo[plot].origin.x, as: Date.self)
                        case .ended:
                            hover = nil
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { v in
                        guard let plot = proxy.plotFrame, let d = proxy.value(atX: v.location.x - geo[plot].origin.x, as: Date.self),
                              let hit = hits(d).first else { return }
                        withAnimation(.snappy) { m.toggle(finding: hit.1) }
                    })
            }
        }
        .frame(height: 190)
        .padding(.top, 24)
    }

    private func tooltip(_ p: TrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.time.formatted(.dateTime.month().day().hour().minute())).font(.caption2).foregroundStyle(.secondary)
            Text(m.metric.title + " " + m.metric.format(p.value)).font(.caption.weight(.semibold).monospacedDigit())
            if showsApp, let a = p.appValue, let app = m.selectedApp {
                Text(app + " " + (m.metric == .power ? PowerMonitor.formatWatts(a) : String(format: "%.1f%%", a)))
                    .font(.caption.monospacedDigit()).foregroundStyle(ChartPalette.app)
            }
            ForEach(hits(p.time), id: \.1.id) { n, f in
                Text("\(n). " + f.title).font(.caption.weight(.medium)).foregroundStyle(f.severity.color).lineLimit(1)
            }
        }
        .padding(6)
        .glassCard(radius: 10)
    }
}

struct RankingChart: View {
    @ObservedObject var m: AnalysisModel
    @State private var hovered: String?

    var body: some View {
        let shares = m.ranking
        let total = max(shares.reduce(0) { $0 + $1.joules }, 0.0001)
        HStack(alignment: .center, spacing: 20) {
            Chart(Array(shares.enumerated()), id: \.element.id) { i, s in
                let focus = m.selectedApp ?? hovered
                SectorMark(angle: .value("Value", s.joules), innerRadius: .ratio(0.62),
                           outerRadius: .ratio(focus == s.name ? 1 : 0.92), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(ChartPalette.color(s, at: i))
                    .opacity(focus == nil || focus == s.name ? 1 : 0.3)
            }
            .frame(width: 160, height: 160)
            .overlay {
                VStack(spacing: 2) {
                    Text(m.rankKind == .memory ? L("峰值", "Peak") : L("合计", "Total")).font(.caption2).foregroundStyle(.secondary)
                    Text(m.rankKind.format(m.rankKind == .memory ? (shares.first?.joules ?? 0) : total, seconds: m.recordedSeconds))
                        .font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6).frame(width: 90)
                }
            }
            .animation(.snappy, value: m.selectedApp)
            .animation(.snappy, value: hovered)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { i, s in
                    row(s, color: ChartPalette.color(s, at: i), share: s.joules / total)
                }
            }
        }
    }

    private func row(_ s: EnergyShare, color: Color, share: Double) -> some View {
        let selected = m.selectedApp == s.name
        return Button { withAnimation(.snappy) { m.toggle(app: s.name) } } label: {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 8, height: 8)
                Image(nsImage: ProcessMemory.icon(s.path)).resizable().frame(width: 16, height: 16)
                Text(ChartPalette.label(s)).lineLimit(1)
                if let v = m.parsed?.verdict(for: s.name) {
                    Image(systemName: v.verdict.icon).font(.caption).foregroundStyle(v.verdict.color)
                    if v.verdict != .expected { Text(v.note).font(.caption).foregroundStyle(v.verdict.color).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(m.rankKind.format(s.joules, seconds: m.recordedSeconds)).foregroundStyle(.secondary)
                if m.rankKind != .memory { Text(String(format: "%.0f%%", share * 100)).frame(width: 40, alignment: .trailing) }
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? color.opacity(0.2) : (hovered == s.name ? Color.primary.opacity(0.06) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? s.name : (hovered == s.name ? nil : hovered) }
        .help(s.name == PowerStats.otherName ? "" : (m.parsed?.verdict(for: s.name).map { $0.verdict.text + "：" + $0.note + "\n" } ?? "") + L("点击在趋势图里查看这个应用", "Click to show this app in the trend chart"))
    }
}

struct DailyEnergyChart: View {
    let days: [DailyEnergy]
    @State private var hover: Date?

    var body: some View {
        let cal = Calendar.current
        let selected = hover.flatMap { h in days.first { cal.isDate($0.day, inSameDayAs: h) } }
        Chart(days) { d in
            BarMark(x: .value("Day", d.day, unit: .day), y: .value("Wh", d.wattHours))
                .foregroundStyle(Color.orange.gradient)
                .opacity(selected == nil || selected?.day == d.day ? 1 : 0.4)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(String(format: "%.0f Wh", d.wattHours)).font(.caption2.monospacedDigit())
                        .foregroundStyle(selected?.day == d.day ? .primary : .secondary)
                }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let w = v.as(Double.self) { Text("\(Int(w)) Wh") } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            guard let plot = proxy.plotFrame else { return }
                            hover = proxy.value(atX: p.x - geo[plot].origin.x, as: Date.self)
                        case .ended:
                            hover = nil
                        }
                    }
            }
        }
        .frame(height: 140)
    }
}
