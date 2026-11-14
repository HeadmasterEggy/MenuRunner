import AppKit

final class CompactCards {
    static let maxWidth: CGFloat = 250
    static let cpuHeight: CGFloat = 118
    static let memoryHeight: CGFloat = 124
    static let networkHeight: CGFloat = 118
    static let powerHeight: CGFloat = 92
    private static let chartTop: CGFloat = 44
    private static let bottomInset: CGFloat = 14
    private static let rowStep: CGFloat = 16

    private let model: StatsModel

    init(model: StatsModel) { self.model = model }

    static func fits(_ w: CGFloat) -> Bool { w < maxWidth }

    func cpu(_ w: CGFloat, height: CGFloat) {
        let m = model
        Draw.title("cpu", "CPU", in: w, tint: .systemBlue)
        Draw.text(Draw.pct(m.v("cpu")), NSPoint(x: w - 14, y: 8), size: 20, weight: .semibold, right: true, mono: true)
        Draw.text(L("系统 ", "Sys ") + Draw.pct(m.v("sys")) + L("  用户 ", "  User ") + Draw.pct(m.v("user")),
                  NSPoint(x: 14, y: 28), size: 10, color: .glassSecondary, mono: true, maxWidth: w - 28)
        let chart = NSRect(x: 14, y: Self.chartTop, width: w - 28, height: height - Self.chartTop - Self.bottomInset)
        Draw.chartBackground(chart)
        Draw.area(chart, m.cpuHistory.map { $0.system + $0.user }, scroll: m.scroll, color: .systemBlue, dot: true)
        Draw.area(chart, m.cpuHistory.map { $0.system }, scroll: m.scroll, color: .systemOrange)
    }

    func memory(_ w: CGFloat, pressure: Int) {
        let m = model
        let titleEnd = Draw.title("memorychip", L("内存", "Memory"), in: w, tint: .systemPurple)
        let (ptext, pcolor): (String, NSColor) = pressure >= 4 ? (L("紧张", "Critical"), .systemRed)
            : (pressure >= 2 ? (L("偏高", "Elevated"), .systemOrange) : (L("正常", "Normal"), .systemGreen))
        let label = NSAttributedString(string: ptext, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: pcolor])
        let bw = label.size().width + 12, bx = max(titleEnd + 8, w - 14 - bw)
        pcolor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: bx, y: 12, width: bw, height: 16), xRadius: 8, yRadius: 8).fill()
        label.draw(at: NSPoint(x: bx + 6, y: 13.5))
        Draw.text("\(SystemInfo.gb(m.v("memUsed"))) / \(SystemInfo.gb(m.memory.total))", NSPoint(x: 14, y: 36), size: 11, color: .glassSecondary, mono: true)
        Draw.text(Draw.pct(m.v("mem")), NSPoint(x: w - 14, y: 36), size: 11, weight: .semibold, right: true, mono: true)
        let bar = NSRect(x: 14, y: 54, width: w - 28, height: 8)
        let shape = NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(0.16).setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        var x = bar.minX
        for (k, c) in [("app", NSColor.systemBlue), ("wired", .systemOrange), ("comp", .systemPurple)] {
            let segment = bar.width * CGFloat(m.v(k))
            c.setFill(); NSRect(x: x, y: bar.minY, width: segment, height: bar.height).fill()
            x += segment
        }
        NSGraphicsContext.restoreGraphicsState()
        var y: CGFloat = 70
        for (name, v, c) in [("App", m.memory.app, NSColor.systemBlue), (L("联动", "Wired"), m.memory.wired, .systemOrange), (L("压缩", "Compressed"), m.memory.compressed, .systemPurple)] {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: 14, y: y + 4, width: 7, height: 7)).fill()
            Draw.text(name, NSPoint(x: 25, y: y), size: 10, color: .glassSecondary)
            Draw.text(SystemInfo.gb(v), NSPoint(x: w - 14, y: y), size: 10, color: .glassSecondary, right: true, mono: true)
            y += Self.rowStep
        }
    }

    func network(_ w: CGFloat, height: CGFloat) {
        let m = model
        Draw.title("network", L("网络", "Network"), in: w, tint: .systemTeal)
        Draw.text("↓ " + NetMonitor.format(m.v("down")), NSPoint(x: 14, y: 30), size: 10, weight: .medium, color: .systemTeal, mono: true)
        Draw.text("↑ " + NetMonitor.format(m.v("up")), NSPoint(x: w - 14, y: 30), size: 10, weight: .medium, color: .systemPink, right: true, mono: true)
        let top = Self.chartTop + 4
        let chart = NSRect(x: 14, y: top, width: w - 28, height: height - top - Self.bottomInset)
        Draw.chartBackground(chart)
        let peak = max(m.netHistory.map { max($0.up, $0.down) }.max() ?? 0, 10 * 1024), scale = peak / Draw.labelHeadroom
        Draw.area(chart, m.netHistory.map { $0.down / scale }, scroll: m.scroll, color: .systemTeal, dot: true)
        Draw.area(chart, m.netHistory.map { $0.up / scale }, scroll: m.scroll, color: .systemPink, line: true)
        Draw.text(L("峰值 ", "Peak ") + NetMonitor.format(peak), NSPoint(x: chart.maxX - 8, y: chart.minY + 3), size: 9, color: .glassTertiary, right: true, mono: true)
    }

    func power(_ w: CGFloat, apps: [AppStat], watts: Double?) {
        Draw.title("bolt.fill", L("功耗", "Power"), in: w, tint: .systemYellow)
        Draw.text(watts.map(PowerMonitor.formatWatts) ?? "--", NSPoint(x: w - 14, y: 9), size: 16, weight: .semibold, right: true, mono: true)
        guard !apps.isEmpty else {
            Draw.text(L("采样中…", "Sampling…"), NSPoint(x: 14, y: 38), size: 10, color: .glassTertiary)
            return
        }
        var y: CGFloat = 38
        for a in apps {
            ProcessMemory.icon(a.path).draw(in: NSRect(x: 14, y: y, width: 12, height: 12), from: .zero, operation: .sourceOver,
                                            fraction: 1, respectFlipped: true, hints: nil)
            let value = PowerMonitor.formatWatts(a.value)
            let valueW = NSAttributedString(string: value, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)]).size().width
            Draw.text(a.name, NSPoint(x: 30, y: y - 1), size: 10, color: .glassSecondary, maxWidth: w - 30 - 14 - valueW - 6)
            Draw.text(value, NSPoint(x: w - 14, y: y - 1), size: 10, weight: .medium, right: true, mono: true)
            y += Self.rowStep
        }
    }
}
