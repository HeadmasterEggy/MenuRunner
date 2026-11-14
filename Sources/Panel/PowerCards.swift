import AppKit

final class PowerCards {
    static let mainHeight: CGFloat = 64
    static let summaryHeight: CGFloat = 132
    static let analysisHeight: CGFloat = 62
    static let appRows = 6
    private static let chartHours = 24
    private static let liveAppsOnCard = 3

    private var recorder: PowerRecorder { .shared }

    func drawMain(_ w: CGFloat) {
        Draw.title("bolt.fill", L("功耗", "Power"), in: w, tint: .systemYellow)
        Draw.text(recorder.liveWatts.map(PowerMonitor.formatWatts) ?? "--", NSPoint(x: w - 14, y: 9), size: 18, weight: .semibold, right: true, mono: true)
        let apps = recorder.liveApps.prefix(Self.liveAppsOnCard)
        guard !apps.isEmpty else {
            Draw.text(L("采样中…", "Sampling…"), NSPoint(x: 14, y: 38), size: 10, color: .glassTertiary)
            return
        }
        let colW = (w - 28) / CGFloat(Self.liveAppsOnCard)
        for (i, a) in apps.enumerated() {
            let x = 14 + CGFloat(i) * colW
            ProcessMemory.icon(a.path).draw(in: NSRect(x: x, y: 38, width: 14, height: 14), from: .zero, operation: .sourceOver,
                                            fraction: 1, respectFlipped: true, hints: nil)
            let value = PowerMonitor.formatWatts(a.value)
            let valueW = NSAttributedString(string: value, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)]).size().width
            Draw.text(a.name, NSPoint(x: x + 18, y: 38), size: 10, color: .glassSecondary, maxWidth: colW - 30 - valueW)
            Draw.text(value, NSPoint(x: x + colW - 6, y: 38), size: 10, weight: .medium, right: true, mono: true)
        }
    }

    func drawSummary(_ w: CGFloat) {
        let stats: [(String, String)] = [
            (L("当前", "Now"), recorder.liveWatts.map(PowerMonitor.formatWatts) ?? "--"),
            (L("24 小时平均", "24 h average"), recorder.averageWatts(hours: 24).map(PowerMonitor.formatWatts) ?? "--"),
            (L("24 小时耗电", "24 h energy"), PowerMonitor.formatEnergy(recorder.systemEnergy(hours: 24))),
        ]
        let colW = (w - 28) / CGFloat(stats.count)
        for (i, (label, value)) in stats.enumerated() {
            let x = 14 + CGFloat(i) * colW
            Draw.text(label, NSPoint(x: x, y: 12), size: 10, color: .glassSecondary)
            Draw.text(value, NSPoint(x: x, y: 26), size: 15, weight: .semibold, mono: true)
        }
        let chart = NSRect(x: 14, y: 56, width: w - 28, height: 62)
        Draw.chartBackground(chart)
        let values = recorder.hourlyWatts(hours: Self.chartHours)
        let peak = max(values.compactMap { $0 }.max() ?? 0, 1)
        let gap: CGFloat = 2, inset: CGFloat = 6, labelRoom: CGFloat = 16
        let bw = (chart.width - inset * 2 - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let h = max(2, (chart.height - inset - labelRoom) * CGFloat(v / peak))
            let x = chart.minX + inset + CGFloat(i) * (bw + gap)
            NSColor.systemYellow.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: chart.maxY - inset - h, width: bw, height: h), xRadius: 2, yRadius: 2).fill()
        }
        Draw.text(L("过去 24 小时 · 峰值 ", "Last 24 h · peak ") + PowerMonitor.formatWatts(peak), NSPoint(x: chart.maxX - 8, y: chart.minY + 3),
                  size: 9, color: .glassTertiary, right: true, mono: true)
    }

    func drawAnalysis(_ w: CGFloat) {
        Draw.symbol("sparkles", NSPoint(x: 14, y: 12), size: 14, color: .systemPurple)
        Draw.text(L("AI 分析", "AI Analysis"), NSPoint(x: 38, y: 12), size: 12, weight: .semibold)
        let span = recorder.recordedSeconds(hours: PowerRecorder.retention / 3600) / 3600
        let status = recorder.enabled ? L("已记录 ", "Recorded ") + AnalysisModel.spanText(span) : L("功耗记录已关闭", "Power recording is off")
        Draw.text(status, NSPoint(x: 38, y: 32), size: 10, color: .glassSecondary)
        Draw.text(L("开始分析 ›", "Analyze ›"), NSPoint(x: w - 14, y: 20), size: 11, weight: .medium, color: .controlAccentColor, right: true)
    }
}
