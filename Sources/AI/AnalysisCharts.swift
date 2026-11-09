import SwiftUI
import Charts

enum ChartPalette {
    static let apps: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .indigo, .mint]
    static let other = Color.gray.opacity(0.6)
    static let power = Color.yellow

    static func color(_ share: EnergyShare, at index: Int) -> Color {
        share.name == PowerStats.otherName ? other : apps[index % apps.count]
    }

    static func label(_ share: EnergyShare) -> String {
        share.name == PowerStats.otherName ? L("其他", "Other") : share.name
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

struct EnergyShareChart: View {
    let shares: [EnergyShare]

    private var total: Double { max(shares.reduce(0) { $0 + $1.joules }, 0.0001) }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Chart(Array(shares.enumerated()), id: \.element.id) { i, s in
                SectorMark(angle: .value("Energy", s.joules), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(ChartPalette.color(s, at: i))
            }
            .frame(width: 150, height: 150)
            .overlay {
                VStack(spacing: 2) {
                    Text(PowerMonitor.formatEnergy(total)).font(.headline.monospacedDigit())
                    Text(L("应用合计", "Apps total")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 7) {
                        Circle().fill(ChartPalette.color(s, at: i)).frame(width: 8, height: 8)
                        Image(nsImage: ProcessMemory.icon(s.path)).resizable().frame(width: 16, height: 16)
                        Text(ChartPalette.label(s)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(PowerMonitor.formatEnergy(s.joules)).foregroundStyle(.secondary)
                        Text(String(format: "%.0f%%", s.joules / total * 100)).frame(width: 40, alignment: .trailing)
                    }
                    .font(.callout.monospacedDigit())
                }
            }
        }
    }
}

struct PowerTrendChart: View {
    let points: [TrendPoint]

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("Time", p.time, unit: .hour), y: .value("W", p.watts))
                .foregroundStyle(LinearGradient(colors: [ChartPalette.power.opacity(0.45), ChartPalette.power.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", p.time, unit: .hour), y: .value("W", p.watts))
                .foregroundStyle(ChartPalette.power)
                .interpolationMethod(.monotone)
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let w = v.as(Double.self) { Text("\(Int(w)) W") } }
            }
        }
        .frame(height: 150)
    }
}

struct DailyEnergyChart: View {
    let days: [DailyEnergy]

    var body: some View {
        Chart(days) { d in
            BarMark(x: .value("Day", d.day, unit: .day), y: .value("Wh", d.wattHours))
                .foregroundStyle(Color.orange.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(String(format: "%.0f", d.wattHours)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let w = v.as(Double.self) { Text("\(Int(w)) Wh") } }
            }
        }
        .frame(height: 130)
    }
}
