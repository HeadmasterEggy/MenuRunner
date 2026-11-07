import AppKit
import SwiftUI
import QuartzCore

final class PanelController: NSObject, NSPopoverDelegate {
    let model: StatsModel
    let popover = NSPopover()
    private var cards: [CardView] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    var onSettings: (NSView) -> Void = { _ in }
    var onVisibilityChange: (Bool) -> Void = { _ in }

    static let width: CGFloat = 340, gap: CGFloat = 10, margin: CGFloat = 10

    init(model: StatsModel) {
        self.model = model
        super.init()
        popover.behavior = .applicationDefined
        if CommandLine.arguments.contains("--light") { popover.appearance = NSAppearance(named: .aqua) }
        popover.animates = true
        popover.delegate = self
        build()
        detail.onUpdate = { [weak self] in self?.settle() }
    }

    private struct Page { let view: NSView; let size: NSSize; let cards: [CardView] }
    private var mainPage: Page!

    private func makePage(_ rows: [(CGFloat, [(CGFloat, CGFloat, (CGFloat) -> Void, (() -> Void)?)])], continuous: Set<Int> = [],
                          button: ((CardView, CGFloat) -> Void)? = nil) -> Page {
        let W = Self.width, g = Self.gap, M = Self.margin
        var layout: [(CGFloat, CGFloat, CGFloat, CGFloat, (CGFloat) -> Void, (() -> Void)?)] = []
        var y: CGFloat = 0
        for (h, items) in rows {
            for (x, w, d, c) in items { layout.append((x, y, w, h, d, c)) }
            y += h + g
        }
        let H = y - g
        let size = NSSize(width: W + M * 2, height: H + M * 2)
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let container = NSGlassEffectContainerView(frame: root.bounds)
        container.spacing = g
        let glassHolder = NSView(frame: root.bounds)
        let contentLayer = NSView(frame: root.bounds)
        var cards: [CardView] = []
        for (i, (x, top, w, h, d, click)) in layout.enumerated() {
            let frame = NSRect(x: M + x, y: M + H - top - h, width: w, height: h)
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = 18
            glass.style = .regular
            glassHolder.addSubview(glass)
            let card = CardView(frame: frame)
            card.drawer = d
            card.onClick = click
            card.continuous = continuous.contains(i)
            contentLayer.addSubview(card)
            cards.append(card)
            if i == 0 { button?(card, w) }
        }
        container.contentView = glassHolder
        root.addSubview(container)
        root.addSubview(contentLayer)
        return Page(view: root, size: size, cards: cards)
    }

    private func build() {
        let W = Self.width, g = Self.gap, half = (W - g) / 2
        mainPage = makePage([
            (56,  [(0, W, drawHeader, { [weak self] in self?.showDetail(.system) })]),
            (134, [(0, W, drawCPU, { [weak self] in self?.showDetail(.cpu) })]),
            (118, [(0, half, drawGPU, { [weak self] in self?.showDetail(.gpu) }), (half + g, half, drawTemps, { [weak self] in self?.showDetail(.temps) })]),
            (84,  [(0, W, drawMemory, { [weak self] in self?.showDetail(.memory) })]),
            (138, [(0, half, drawStorage, { [weak self] in self?.showDetail(.storage) }), (half + g, half, drawBattery, { [weak self] in self?.showDetail(.battery) })]),
            (96,  [(0, W, drawNetwork, { [weak self] in self?.showDetail(.network) })]),
        ], continuous: [1, 2, 7],
           button: { [weak self] card, w in
            guard let self else { return }
            let b = NSButton(image: NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")!,
                             target: self, action: #selector(self.settingsClicked(_:)))
            b.isBordered = false
            b.contentTintColor = .labelColor
            b.frame = NSRect(x: w - 38, y: 16, width: 24, height: 24)
            card.addSubview(b)
        })
        cards = mainPage.cards
        host = NSView(frame: NSRect(origin: .zero, size: mainPage.size))
        mainPage.view.autoresizingMask = [.minYMargin]
        host.addSubview(mainPage.view)
        current = mainPage.view
        let vc = NSViewController()
        vc.view = host
        popover.contentViewController = vc
        popover.contentSize = mainPage.size
    }

    static let procRows = 8, topProcRows = 10
    let detail = DetailProvider()
    private var detailKind: DetailKind = .memory
    private var detailPages: [String: Page] = [:]
    private var detailTimer: Timer?
    private var kvRows: [(String, String)] = []

    func debugShow(_ k: DetailKind) { showDetail(k) }

    var settingsModel: SettingsModel?
    private var settingsPage: Page?

    func showSettings() {
        guard let m = settingsModel else { return }
        let page = settingsPage ?? {
            let W = Self.width, M = Self.margin, g = Self.gap
            let header = makePage([(56, [(0, W, { [weak self] w in self?.drawSettingsHeader(w) }, nil)])], button: { [weak self] card, _ in
                guard let self else { return }
                let b = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
                                 target: self, action: #selector(self.backToMain))
                b.isBordered = false
                b.contentTintColor = .labelColor
                b.frame = NSRect(x: 10, y: 16, width: 24, height: 24)
                card.addSubview(b)
            })
            let formH: CGFloat = 600
            let size = NSSize(width: header.size.width, height: header.size.height + g + formH)
            let root = NSView(frame: NSRect(origin: .zero, size: size))
            header.view.setFrameOrigin(NSPoint(x: 0, y: size.height - header.size.height))
            root.addSubview(header.view)
            let host = NSHostingView(rootView: SettingsView(m: m, width: W + M * 2 - 8, height: formH))
            host.frame = NSRect(x: 4, y: 0, width: W + M * 2 - 8, height: formH)
            root.addSubview(host)
            let p = Page(view: root, size: size, cards: header.cards)
            settingsPage = p
            return p
        }()
        switchTo(page)
    }

    private func drawSettingsHeader(_ w: CGFloat) {
        Draw.symbol("gearshape.fill", NSPoint(x: 40, y: 10), size: 15, color: .glassSecondary)
        Draw.text(L("设置", "Settings"), NSPoint(x: 64, y: 8), size: 13, weight: .semibold)
        Draw.text("MenuRunner " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
                  NSPoint(x: 64, y: 29), size: 10, color: .glassSecondary)
    }
    var debugMainView: NSView { mainPage.view }
    var debugCardFrames: [NSRect] { mainPage.cards.map { $0.frame } }

    private func key(_ k: DetailKind) -> String { "\(k)" }

    private func showDetail(_ k: DetailKind) {
        detailKind = k
        detail.reset()
        refreshDetail(wait: true)
        let W = Self.width
        let dynamic = k == .storage || k == .temps || k == .system || k == .battery || k == .network
        let page = (dynamic ? nil : detailPages[key(k)]) ?? {
            let header: (CGFloat, [(CGFloat, CGFloat, (CGFloat) -> Void, (() -> Void)?)]) = (56, [(0, W, drawDetailHeader, nil)])
            var rows = [header]
            switch k {
            case .system, .battery: rows.append((CGFloat(max(1, kvRows.count)) * 24 + 14, [(0, W, drawKV, nil)]))
            case .cpu:     rows += [(132, [(0, W, drawCores, nil)]), (8 * 30 + 46, [(0, W, { [weak self] w in self?.drawApps(w, L("占用 CPU 最多的应用", "Top apps by CPU"), self?.detail.cpuApps ?? [], { String(format: "%.1f%%", $0 * 100) }) }, nil)])]
            case .gpu:     rows += [(4 * 24 + 46, [(0, W, drawGPUStats, nil)]), (8 * 30 + 46, [(0, W, { [weak self] w in self?.drawApps(w, L("占用 GPU 最多的应用", "Top apps by GPU"), self?.detail.gpuApps ?? [], { String(format: "%.1f%%", $0 * 100) }) }, nil)])]
            case .memory:  rows += [(CGFloat(Self.procRows) * 30 + 46, [(0, W, drawProcessList, nil)]),
                                    (CGFloat(Self.topProcRows) * 30 + 46, [(0, W, drawTopProcs, nil)])]
            case .temps:   rows.append((CGFloat(max(1, min(14, (detail.sensors.count + 1) / 2))) * 22 + 24, [(0, W, drawSensors, nil)]))
            case .storage: rows += [(CGFloat(max(1, detail.volumes.count)) * 46 + 14, [(0, W, drawVolumes, nil)]),
                                    (12 * 30 + 46, [(0, W, drawAppSizes, nil)])]
            case .network: rows += [(CGFloat(max(1, detail.interfaces.count)) * 40 + 40, [(0, W, drawInterfaces, nil)]), (8 * 30 + 46, [(0, W, { [weak self] w in self?.drawApps(w, L("网络流量最大的应用", "Top apps by network"), self?.detail.netApps ?? [], { NetMonitor.format($0) }) }, nil)])]
            }
            let p = makePage(rows, button: { [weak self] card, _ in
                guard let self else { return }
                let b = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
                                 target: self, action: #selector(self.backToMain))
                b.isBordered = false
                b.contentTintColor = .labelColor
                b.frame = NSRect(x: 10, y: 16, width: 24, height: 24)
                card.addSubview(b)
            })
            if let list = p.cards.last {
                switch k {
                case .memory:
                    list.rowAt = { [weak self] pt in self.flatMap { $0.rowHit(pt, top: 36, paths: $0.detail.memProcs.map { $0.path }) } }
                    p.cards[p.cards.count - 2].rowAt = { [weak self] pt in self.flatMap { $0.rowHit(pt, top: 36, paths: $0.detail.memApps.map { $0.path }) } }
                case .cpu, .gpu, .network, .storage:
                    list.rowAt = { [weak self] pt in
                        guard let self else { return nil }
                        let apps = k == .cpu ? self.detail.cpuApps : k == .gpu ? self.detail.gpuApps : k == .network ? self.detail.netApps : self.detail.appSizes
                        return self.rowHit(pt, top: 36, paths: apps.map { $0.path })
                    }
                default: break
                }
            }
            detailPages[key(k)] = p
            return p
        }()
        switchTo(page)
        detailTimer?.invalidate()
        let interval: Double = (k == .memory || k == .storage || k == .system) ? 2 : 1.5
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refreshDetail() }
        RunLoop.main.add(t, forMode: .common)
        detailTimer = t
    }

    private func refreshDetail(wait: Bool = false) {
        detail.refresh(detailKind, wait: wait)
        settle()
        switch detailKind {
        case .system:  kvRows = SystemDetail.rows(spec)
        case .battery: kvRows = BatteryDetail.rows()
        default: break
        }
    }

    @objc private func backToMain() {
        detailTimer?.invalidate(); detailTimer = nil
        detail.stopNetwork()
        switchTo(mainPage, forward: false, animated: popover.isShown)
    }

    private var detailTitle: (icon: String, tint: NSColor, title: String, value: String, sub: String) {
        let m = model
        switch detailKind {
        case .system:  return ("laptopcomputer", .labelColor, spec.model, "", spec.summary)
        case .cpu:     return ("cpu", .systemBlue, "CPU", Draw.pct(m.v("cpu")), spec.detail.components(separatedBy: " · ").first ?? "")
        case .gpu:     return ("cpu.fill", .systemGreen, "GPU", m.gpu == nil ? "--" : Draw.pct(m.v("gpu")), spec.gpuCores > 0 ? L("\(spec.gpuCores) 核 GPU", "\(spec.gpuCores)-core GPU") : "")
        case .memory:  return ("memorychip", .systemPurple, L("内存占用", "Memory Usage"), "\(SystemInfo.gb(m.memory.used)) / \(SystemInfo.gb(m.memory.total))", L("应用 · 进程", "Apps · processes"))
        case .temps:   return ("thermometer.medium", .systemOrange, L("温度传感器", "Temperature Sensors"), m.temps.soc.map { TempUnit.format($0) } ?? "--", L("\(detail.sensors.count) 个传感器", "\(detail.sensors.count) sensors"))
        case .storage: return ("internaldrive", .systemIndigo, L("存储", "Storage"), m.storage.map { Draw.pct($0.used / $0.total) } ?? "--", L("已挂载的卷", "Mounted volumes"))
        case .battery: return ("battery.100", .systemGreen, L("电池", "Battery"), m.battery.map { "\($0.percent)%" } ?? "--", m.battery.map { SystemInfo.stateText($0.state) } ?? "")
        case .network: return ("network", .systemTeal, L("网络", "Network"), "↓ " + NetMonitor.format(m.v("down")), "↑ " + NetMonitor.format(m.v("up")))
        }
    }

    private func drawDetailHeader(_ w: CGFloat) {
        let h = detailTitle
        Draw.symbol(h.icon, NSPoint(x: 40, y: 10), size: 15, color: h.tint)
        Draw.text(h.title, NSPoint(x: 64, y: 8), size: 13, weight: .semibold)
        Draw.text(h.sub, NSPoint(x: 64, y: 29), size: 10, color: .glassSecondary)
        Draw.text(h.value, NSPoint(x: w - 14, y: 12), size: 15, weight: .semibold, right: true, mono: true)
    }

    private func rowHighlight(_ y: CGFloat, _ w: CGFloat, clickable: Bool) {
        guard clickable, let h = CardView.drawingHover, h.y >= y - 4, h.y < y + 26 else { return }
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: y - 4, width: w - 16, height: 30), xRadius: 8, yRadius: 8).fill()
    }

    private func rowHit(_ p: NSPoint, top: CGFloat, paths: [String?]) -> String? {
        guard p.y >= top - 4 else { return nil }
        let i = Int((p.y - top + 4) / 30)
        return i < paths.count ? paths[i] : nil
    }

    private func sectionTitle(_ s: String) { Draw.text(s, NSPoint(x: 14, y: 12), size: 11, weight: .semibold, color: .glassSecondary) }

    private func drawKV(_ w: CGFloat) {
        var y: CGFloat = 12
        for (k, v) in kvRows {
            Draw.text(k, NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
            Draw.text(v, NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true)
            y += 24
        }
    }

    private func drawCores(_ w: CGFloat) {
        sectionTitle(L("每个核心", "Per core"))
        let cores = detail.cores
        guard !cores.isEmpty else { Draw.text(L("采样中…", "Sampling…"), NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return }
        let e = spec.eCores, n = cores.count
        let gap: CGFloat = 6, bw = (w - 28 - gap * CGFloat(n - 1)) / CGFloat(n)
        let top: CGFloat = 36, h: CGFloat = 64
        for (i, v) in cores.enumerated() {
            let x = 14 + CGFloat(i) * (bw + gap)
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: top, width: bw, height: h), xRadius: 4, yRadius: 4).fill()
            let isE = i < e
            (isE ? NSColor.systemTeal : NSColor.systemBlue).setFill()
            let fh = max(3, h * CGFloat(min(v, 1)))
            NSBezierPath(roundedRect: NSRect(x: x, y: top + h - fh, width: bw, height: fh), xRadius: 4, yRadius: 4).fill()
            let label = isE ? "E\(i + 1)" : "P\(i - e + 1)"
            let ls = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.glassSecondary])
            ls.draw(at: NSPoint(x: x + (bw - ls.size().width) / 2, y: top + h + 4))
            let vs = NSAttributedString(string: "\(Int(v * 100))", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular), .foregroundColor: NSColor.glassTertiary])
            vs.draw(at: NSPoint(x: x + (bw - vs.size().width) / 2, y: top + h + 16))
        }
    }

    private func drawApps(_ w: CGFloat, _ title: String, _ apps: [AppStat], _ fmt: (Double) -> String) {
        sectionTitle(title)
        guard !apps.isEmpty else {
            let hint = detailKind == .network ? L("采样中…（约 2 秒）", "Sampling… (about 2 s)") : L("采样中…", "Sampling…")
            Draw.text(hint, NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return
        }
        let maxV = max(apps.first?.value ?? 1, 0.0001)
        var y: CGFloat = 36
        for a in apps {
            rowHighlight(y, w, clickable: a.path != nil)
            ProcessMemory.icon(a.path).draw(in: NSRect(x: 14, y: y, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Draw.text(a.processes > 1 ? "\(a.name)  ×\(a.processes)" : a.name, NSPoint(x: 42, y: y + 1), size: 12, weight: .medium)
            Draw.text(fmt(a.value), NSPoint(x: w - 14, y: y + 1), size: 12, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 42, y: y + 20, width: w - 56, height: 3), a.value / maxV, .systemBlue)
            y += 30
        }
    }

    private func drawGPUStats(_ w: CGFloat) {
        sectionTitle(L("利用率", "Utilization"))
        var y: CGFloat = 36
        for (k, label) in [("Device Utilization %", L("设备", "Device")), ("Renderer Utilization %", L("渲染器", "Renderer")), ("Tiler Utilization %", "Tiler")] {
            let v = Double(detail.gpuStats[k] ?? 0) / 100
            Draw.text(label, NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
            Draw.text(Draw.pct(v), NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 90, y: y + 6, width: w - 150, height: 5), v, .systemGreen)
            y += 24
        }
        let mem = Double(detail.gpuStats["In use system memory"] ?? 0)
        Draw.text(L("显存（共享内存）", "GPU memory (shared)"), NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
        Draw.text(SystemInfo.gb(mem), NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true, mono: true)
    }

    private func drawSensors(_ w: CGFloat) {
        let s = detail.sensors
        guard !s.isEmpty else { Draw.text(L("读取不到温度传感器", "No temperature sensors available"), NSPoint(x: 14, y: 14), size: 11, color: .glassTertiary); return }
        let colW = (w - 28 - 16) / 2, perCol = 14
        for (i, (name, v)) in s.prefix(perCol * 2).enumerated() {
            let x = 14 + CGFloat(i / perCol) * (colW + 16), y = 12 + CGFloat(i % perCol) * 22
            Draw.text(name, NSPoint(x: x, y: y), size: 10, color: .glassSecondary)
            Draw.text(TempUnit.format(v), NSPoint(x: x + colW, y: y), size: 10, weight: .medium, color: Draw.tempColor(v), right: true, mono: true)
        }
    }

    private func drawAppSizes(_ w: CGFloat) {
        let apps = detail.appSizes
        if apps.isEmpty {
            sectionTitle(L("应用占用空间", "Space used by apps"))
            Draw.text(detail.sizeScanning ? L("正在计算应用大小…", "Calculating app sizes…") : "", NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary)
            return
        }
        drawApps(w, L("应用占用空间（从大到小）", "Space used by apps (largest first)"), apps, { ProcessMemory.format(UInt64($0)) })
    }

    private func drawVolumes(_ w: CGFloat) {
        var y: CGFloat = 12
        for v in detail.volumes {
            ProcessMemory.icon(v.path).draw(in: NSRect(x: 14, y: y, width: 24, height: 24), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Draw.text(v.name, NSPoint(x: 46, y: y), size: 12, weight: .medium)
            Draw.text("\(SystemInfo.gb(v.used)) / \(SystemInfo.gb(v.total))", NSPoint(x: w - 14, y: y), size: 11, color: .glassSecondary, right: true, mono: true)
            let f = v.used / v.total
            Draw.bar(NSRect(x: 46, y: y + 22, width: w - 60, height: 5), f, Draw.level(f))
            y += 46
        }
    }

    private func drawInterfaces(_ w: CGFloat) {
        sectionTitle(L("网络接口", "Interfaces"))
        guard !detail.interfaces.isEmpty else { Draw.text(L("未连接", "Not connected"), NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return }
        var y: CGFloat = 36
        for i in detail.interfaces {
            Draw.text("\(i.name)  (\(i.bsd))", NSPoint(x: 14, y: y), size: 12, weight: .medium)
            Draw.text(i.ipv4, NSPoint(x: w - 14, y: y), size: 11, color: .glassSecondary, right: true, mono: true)
            Draw.text("↑ " + NetMonitor.format(i.up), NSPoint(x: 14, y: y + 17), size: 10, color: .systemPink, mono: true)
            Draw.text("↓ " + NetMonitor.format(i.down), NSPoint(x: 120, y: y + 17), size: 10, color: .systemTeal, mono: true)
            y += 40
        }
    }

    private var host: NSView!
    private var current: NSView?

    private func switchTo(_ page: Page, forward: Bool = true, animated: Bool = true) {
        cards = page.cards
        settle()
        guard let old = current, old !== page.view else { return }
        let dx: CGFloat = 36
        host.setFrameSize(page.size)
        old.setFrameOrigin(NSPoint(x: 0, y: page.size.height - old.frame.height))
        page.view.setFrameOrigin(NSPoint(x: animated ? (forward ? dx : -dx) : 0, y: 0))
        page.view.alphaValue = animated ? 0 : 1
        host.addSubview(page.view)
        current = page.view
        popover.contentSize = page.size
        let finish = {
            old.removeFromSuperview(); old.alphaValue = 1; old.setFrameOrigin(.zero)
            page.view.window?.invalidateCursorRects(for: page.view)
        }
        guard animated, !CommandLine.arguments.contains("--no-anim") else { finish(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            ctx.allowsImplicitAnimation = true
            page.view.animator().alphaValue = 1
            page.view.animator().setFrameOrigin(NSPoint(x: 0, y: page.view.frame.minY))
            old.animator().alphaValue = 0
            old.animator().setFrameOrigin(NSPoint(x: forward ? -dx : dx, y: old.frame.minY))
        }, completionHandler: finish)
    }

    private func drawProcessList(_ w: CGFloat) {
        let total = Double(model.memory.total)
        let procs = detail.memApps
        let maxBytes = Double(procs.first?.bytes ?? 1)
        sectionTitle(L("按应用汇总", "By app"))
        var y: CGFloat = 36
        for p in procs {
            rowHighlight(y, w, clickable: p.path != nil)
            ProcessMemory.icon(p.path).draw(in: NSRect(x: 14, y: y, width: 20, height: 20), from: .zero, operation: .sourceOver,
                                            fraction: 1, respectFlipped: true, hints: nil)
            let name = p.processes > 1 ? "\(p.name)  ×\(p.processes)" : p.name
            Draw.text(name, NSPoint(x: 42, y: y + 1), size: 12, weight: .medium)
            Draw.text(ProcessMemory.format(p.bytes), NSPoint(x: w - 14, y: y + 1), size: 12, weight: .medium, right: true, mono: true)
            let f = Double(p.bytes) / maxBytes
            Draw.bar(NSRect(x: 42, y: y + 20, width: w - 56, height: 3), f,
                     Double(p.bytes) / total > 0.15 ? .systemOrange : .systemPurple)
            y += 30
        }
    }

    private func drawTopProcs(_ w: CGFloat) {
        sectionTitle(L("占内存最多的进程（含系统进程）", "Top processes (incl. system)"))
        let procs = detail.memProcs, total = Double(model.memory.total)
        guard !procs.isEmpty else { Draw.text(L("采样中…", "Sampling…"), NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return }
        let maxBytes = Double(max(procs.first?.bytes ?? 1, 1)), me = NSUserName()
        var y: CGFloat = 36
        for p in procs {
            rowHighlight(y, w, clickable: p.path != nil)
            ProcessMemory.icon(p.path).draw(in: NSRect(x: 14, y: y, width: 20, height: 20), from: .zero, operation: .sourceOver,
                                            fraction: 1, respectFlipped: true, hints: nil)
            let value = ProcessMemory.format(p.bytes)
            var nameW = w - 56 - 70
            if p.user != me {
                let tag = p.user.hasPrefix("_") ? String(p.user.dropFirst()) : p.user
                Draw.text(tag, NSPoint(x: w - 14 - 78, y: y + 3), size: 9, color: .glassTertiary, right: true)
                nameW -= 70
            }
            Draw.text(p.name, NSPoint(x: 42, y: y + 1), size: 12, weight: .medium, maxWidth: nameW)
            Draw.text(value, NSPoint(x: w - 14, y: y + 1), size: 12, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 42, y: y + 20, width: w - 56, height: 3), Double(p.bytes) / maxBytes,
                     Double(p.bytes) / total > 0.15 ? .systemOrange : .systemPurple)
            y += 30
        }
    }

    @objc private func settingsClicked(_ sender: NSButton) { onSettings(sender) }

    private(set) var isOpen = false
    var isVisible: Bool { isOpen }
    var onMainPage: Bool { cards.first === mainPage.cards.first }

    func sampleMain(pressure: Int) {
        settle()
        memoryPressure = pressure
        if isVisible && onMainPage { detail.refresh(.cpu) }
    }

    func show(below button: NSStatusBarButton) {
        if popover.isShown { popover.close() }
        isOpen = true
        model.resetShown()
        settle(); settleUntil += 0.6
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        detail.prime()
        startTimer()
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.hide()
            }
        }
        onVisibilityChange(true)
    }

    func hide() {
        guard isOpen else { return }
        isOpen = false
        popover.performClose(nil)
    }

    private var outsideMonitor: Any?

    func popoverWillClose(_ notification: Notification) { isOpen = false }

    func popoverDidClose(_ notification: Notification) {
        guard !isOpen else { return }
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        timer?.invalidate(); timer = nil
        if cards.first !== mainPage.cards.first { backToMain() }
        onVisibilityChange(false)
    }

    private func startTimer() {
        timer?.invalidate()
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var frameCount = 0
    private var settleUntil: CFTimeInterval = 0
    func settle() { settleUntil = CACurrentMediaTime() + 0.8 }
    private func frame() {
        frameCount += 1
        if CommandLine.arguments.contains("--open-panel"), frameCount % 60 == 0 {
            NSLog("panel debug: frames=%d cards=%d host=%@ content=%@ win=%@ subviews=%d", frameCount, cards.count,
                  NSStringFromSize(host.frame.size), NSStringFromSize(popover.contentSize),
                  NSStringFromSize(host.window?.frame.size ?? .zero), host.subviews.count)
        }
        let now = CACurrentMediaTime()
        model.tick(dt: now - lastTick); lastTick = now
        let settling = now < settleUntil
        for c in cards where c.continuous || settling { c.needsDisplay = true }
        if onMainPage, model.battery?.state == "charging", mainPage.cards.count > 6 { mainPage.cards[6].needsDisplay = true }
    }

    func redrawAll() { cards.forEach { $0.needsDisplay = true; $0.displayIfNeeded() } }

    var spec = MachineSpec.basic()

    private func drawHeader(_ w: CGFloat) {
        let icon = spec.model.contains("Book") ? "laptopcomputer" : (spec.model.contains("iMac") ? "desktopcomputer" : "macmini")
        Draw.symbol(icon, NSPoint(x: 14, y: 10), size: 15, color: .labelColor)
        Draw.text(spec.model, NSPoint(x: 42, y: 8), size: 13, weight: .semibold)
        let mw = NSAttributedString(string: spec.model, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).size().width
        Draw.text(spec.summary, NSPoint(x: 42 + mw + 8, y: 9), size: 12, weight: .medium, color: .glassSecondary)
        Draw.text(spec.detail, NSPoint(x: 42, y: 29), size: 10, color: .glassSecondary)
    }

    private func drawCPU(_ w: CGFloat) {
        let m = model
        Draw.title("cpu", "CPU", in: w, tint: .systemBlue)
        Draw.text(Draw.pct(m.v("cpu")), NSPoint(x: w - 14, y: 6), size: 24, weight: .semibold, right: true, mono: true)
        if let top = detail.cpuApps.first, onMainPage {
            ProcessMemory.icon(top.path).draw(in: NSRect(x: 14, y: 29, width: 12, height: 12), from: .zero, operation: .sourceOver,
                                              fraction: 1, respectFlipped: true, hints: nil)
            let cores = Double(max(spec.pCores + spec.eCores, 1))
            Draw.text(L("最忙：", "Busiest: ") + top.name + String(format: "  %.0f%%", top.value / cores * 100),
                      NSPoint(x: 30, y: 28), size: 10, color: .glassSecondary)
        }
        let chart = NSRect(x: 14, y: 44, width: w - 28, height: 56)
        Draw.chartBackground(chart)
        Draw.area(chart, m.cpuHistory.map { $0.system + $0.user }, scroll: m.scroll, color: .systemBlue, dot: true)
        Draw.area(chart, m.cpuHistory.map { $0.system }, scroll: m.scroll, color: .systemOrange)
        var x: CGFloat = 14
        for (name, key, c) in [("System", "sys", NSColor.systemOrange), ("User", "user", .systemBlue), ("Idle", "idle", .glassTertiary)] {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 112, width: 7, height: 7)).fill()
            Draw.text("\(name) \(Draw.pct(m.v(key)))", NSPoint(x: x + 11, y: 108), size: 11, color: .glassSecondary, mono: true)
            x += (w - 28) / 3
        }
    }

    private func drawGPU(_ w: CGFloat) {
        let m = model
        Draw.title("cpu.fill", "GPU", in: w, tint: .systemGreen)
        Draw.text(m.gpu == nil ? "--" : Draw.pct(m.v("gpu")), NSPoint(x: w - 14, y: 8), size: 20, weight: .semibold, right: true, mono: true)
        if let mem = gpuMemory {
            Draw.text(L("显存 ", "GPU mem ") + SystemInfo.gb(mem), NSPoint(x: 14, y: 28), size: 10, color: .glassSecondary)
        }
        let chart = NSRect(x: 14, y: 44, width: w - 28, height: 60)
        Draw.chartBackground(chart)
        Draw.area(chart, m.gpuHistory, scroll: m.scroll, color: .systemGreen, dot: true)
    }

    private func drawTemps(_ w: CGFloat) {
        let m = model
        Draw.title("thermometer.medium", L("温度", "Temp"), in: w, tint: .systemOrange)
        let (ttext, tcolor): (String, NSColor) = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal:  return (L("正常", "Normal"), .systemGreen)
            case .fair:     return (L("偏热", "Warm"), .systemYellow)
            case .serious:  return (L("很热", "Hot"), .systemOrange)
            case .critical: return (L("过热", "Critical"), .systemRed)
            @unknown default: return ("--", .glassSecondary)
            }
        }()
        let tl = NSAttributedString(string: ttext, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: tcolor])
        let tw = tl.size().width + 12
        tcolor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: w - 14 - tw, y: 12, width: tw, height: 16), xRadius: 8, yRadius: 8).fill()
        tl.draw(at: NSPoint(x: w - 14 - tw + 6, y: 13.5))
        var y: CGFloat = 40
        for (name, key, has) in [(L("芯片", "SoC"), "tSoc", m.temps.soc != nil), (L("电池", "Battery"), "tBat", m.temps.battery != nil), ("SSD", "tSsd", m.temps.ssd != nil)] {
            let c = m.v(key)
            Draw.text(name, NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
            Draw.text(has ? TempUnit.format(c) : "--", NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 14, y: y + 17, width: w - 28, height: 4), has ? (c - 20) / 80 : 0, Draw.tempColor(c))
            y += 25
        }
    }

    var memoryPressure = 1
    var gpuMemory: Double?
    var netTotals: (up: Double, down: Double) = (0, 0)

    private func drawMemory(_ w: CGFloat) {
        let m = model
        Draw.title("memorychip", L("内存", "Memory"), in: w, tint: .systemPurple)
        let level = memoryPressure
        let (ptext, pcolor): (String, NSColor) = level >= 4 ? (L("压力紧张", "Critical"), .systemRed)
            : (level >= 2 ? (L("压力偏高", "Elevated"), .systemOrange) : (L("压力正常", "Normal"), .systemGreen))
        let titleW = NSAttributedString(string: L("内存", "Memory"), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
        let label = NSAttributedString(string: ptext,
                                       attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: pcolor])
        let bx = 14 + 18 + 6 + titleW + 18, bw = label.size().width + 12
        pcolor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: bx, y: 12, width: bw, height: 16), xRadius: 8, yRadius: 8).fill()
        label.draw(at: NSPoint(x: bx + 6, y: 13.5))
        Draw.text("\(SystemInfo.gb(m.v("memUsed"))) / \(SystemInfo.gb(m.memory.total))  \(Draw.pct(m.v("mem")))",
                  NSPoint(x: w - 14, y: 13), size: 11, color: .glassSecondary, right: true, mono: true)
        let bar = NSRect(x: 14, y: 40, width: w - 28, height: 10)
        let shape = NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.16).setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        var x = bar.minX
        for (k, c) in [("app", NSColor.systemBlue), ("wired", .systemOrange), ("comp", .systemPurple)] {
            let bw = bar.width * CGFloat(m.v(k))
            c.setFill(); NSRect(x: x, y: bar.minY, width: bw, height: bar.height).fill()
            x += bw
        }
        NSGraphicsContext.restoreGraphicsState()
        var lx: CGFloat = 14
        for (name, v, c) in [("App", m.memory.app, NSColor.systemBlue), (L("联动", "Wired"), m.memory.wired, .systemOrange), (L("压缩", "Compressed"), m.memory.compressed, .systemPurple)] {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: lx, y: 64, width: 7, height: 7)).fill()
            Draw.text("\(name) \(SystemInfo.gb(v))", NSPoint(x: lx + 11, y: 60), size: 10, color: .glassSecondary, mono: true)
            lx += (w - 28) / 3
        }
    }

    private func drawStorage(_ w: CGFloat) {
        let m = model
        Draw.title("internaldrive", L("存储", "Storage"), in: w, tint: .systemIndigo)
        guard let st = m.storage else { return }
        let f = m.v("disk")
        let center = NSPoint(x: 44, y: 84), r: CGFloat = 26
        let ring = NSBezierPath(); ring.lineWidth = 8
        ring.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        NSColor.labelColor.withAlphaComponent(0.16).setStroke(); ring.stroke()
        let arc = NSBezierPath(); arc.lineWidth = 8; arc.lineCapStyle = .round
        arc.appendArc(withCenter: center, radius: r, startAngle: -90, endAngle: -90 + 360 * CGFloat(f), clockwise: false)
        Draw.level(f).setStroke(); arc.stroke()
        let s = NSAttributedString(string: Draw.pct(f), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        s.draw(at: NSPoint(x: center.x - s.size().width / 2, y: center.y - s.size().height / 2))
        Draw.text(L("已用", "Used"), NSPoint(x: 84, y: 58), size: 10, color: .glassSecondary)
        Draw.text(SystemInfo.gb(st.used), NSPoint(x: 84, y: 71), size: 11, weight: .medium, mono: true)
        Draw.text(L("可用", "Free"), NSPoint(x: 84, y: 88), size: 10, color: .glassSecondary)
        Draw.text(SystemInfo.gb(st.total - st.used), NSPoint(x: 84, y: 101), size: 11, weight: .medium, mono: true)
    }

    private var batteryTime: (label: String, value: String)?
    func updateBatteryTime() { batteryTime = SystemInfo.batteryTime() }
    func setBatteryTime(_ t: (label: String, value: String)?) { batteryTime = t }

    private func drawBattery(_ w: CGFloat) {
        let m = model
        Draw.title("battery.100", L("电池", "Battery"), in: w, tint: .systemGreen)
        guard let b = m.battery else {
            Draw.text(L("无电池", "No battery"), NSPoint(x: 14, y: 44), size: 11, color: .glassSecondary); return
        }
        let f = m.v("bat")
        let body = NSRect(x: 14, y: 40, width: 46, height: 22)
        let outline = NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6)
        outline.lineWidth = 1.5; NSColor.glassSecondary.setStroke(); outline.stroke()
        NSColor.glassSecondary.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 2, y: body.midY - 4, width: 3, height: 8), xRadius: 1.5, yRadius: 1.5).fill()
        let base: NSColor = b.percent <= 20 ? .systemRed : (b.percent <= 40 ? .systemYellow : .systemGreen)
        let pulse = b.state == "charging" ? 0.65 + 0.35 * (0.5 + 0.5 * sin(CACurrentMediaTime() * 3)) : 1
        base.withAlphaComponent(pulse).setFill()
        NSBezierPath(roundedRect: NSRect(x: body.minX + 3, y: body.minY + 3, width: (body.width - 6) * CGFloat(f), height: body.height - 6),
                     xRadius: 3, yRadius: 3).fill()
        if b.state == "charging" { Draw.symbol("bolt.fill", NSPoint(x: body.midX - 6, y: body.minY + 3), size: 11, color: .white) }
        Draw.text(Draw.pct(f), NSPoint(x: w - 14, y: 41), size: 18, weight: .semibold, right: true, mono: true)
        if m.temps.battery != nil {
            Draw.text(TempUnit.format(m.v("tBat")), NSPoint(x: w - 14, y: 13), size: 10, weight: .medium, color: .glassSecondary, right: true, mono: true)
        }
        let titleW = 14 + 22 + 6 + NSAttributedString(string: L("电池", "Battery"), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
        if b.state == "charging" { Draw.symbol("bolt.fill", NSPoint(x: titleW + 4, y: 12), size: 10, color: .systemYellow) }
        else if b.state == "ac"  { Draw.symbol("powerplug.fill", NSPoint(x: titleW + 4, y: 12), size: 10, color: .glassSecondary) }
        if let h = m.health {
            Draw.text(L("健康度", "Health"), NSPoint(x: 14, y: 72), size: 10, color: .glassSecondary)
            Draw.text(Draw.pct(m.v("health")), NSPoint(x: w - 14, y: 71), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 14, y: 87, width: w - 28, height: 4), m.v("health"), m.v("health") >= 0.8 ? .systemGreen : (m.v("health") >= 0.6 ? .systemYellow : .systemRed))
            Draw.text(L("循环次数", "Cycles"), NSPoint(x: 14, y: 96), size: 10, color: .glassSecondary)
            Draw.text("\(h.cycles) / \(h.designCycles)", NSPoint(x: w - 14, y: 95), size: 11, weight: .medium, right: true, mono: true)
        }
        if let t = batteryTime {
            Draw.text(t.label, NSPoint(x: 14, y: 116), size: 10, color: .glassSecondary)
            Draw.text(t.value, NSPoint(x: w - 14, y: 115), size: 11, weight: .medium, right: true)
        }
    }

    private func drawNetwork(_ w: CGFloat) {
        let m = model
        Draw.title("network", L("网络", "Network"), in: w, tint: .systemTeal)
        Draw.text("↓ " + NetMonitor.format(m.v("down")), NSPoint(x: w - 14, y: 13), size: 11, weight: .medium, color: .systemTeal, right: true, mono: true)
        Draw.text("↑ " + NetMonitor.format(m.v("up")), NSPoint(x: w - 120, y: 13), size: 11, weight: .medium, color: .systemPink, right: true, mono: true)
        let chart = NSRect(x: 14, y: 40, width: w - 28, height: 42)
        Draw.chartBackground(chart)
        let peak = max(m.netHistory.map { max($0.up, $0.down) }.max() ?? 0, 10 * 1024)
        Draw.area(chart, m.netHistory.map { $0.down / peak }, scroll: m.scroll, color: .systemTeal, dot: true)
        Draw.area(chart, m.netHistory.map { $0.up / peak }, scroll: m.scroll, color: .systemPink, line: true)
        Draw.text(L("峰值 ", "Peak ") + NetMonitor.format(peak), NSPoint(x: chart.maxX - 6, y: chart.minY + 3), size: 9, color: .glassTertiary, right: true, mono: true)
        func bytes(_ b: Double) -> String { b >= 1_073_741_824 ? String(format: "%.2f GB", b / 1_073_741_824) : String(format: "%.0f MB", b / 1_048_576) }
        Draw.text(L("本次 ", "Session ") + "↑ " + bytes(netTotals.up) + "  ↓ " + bytes(netTotals.down),
                  NSPoint(x: chart.minX + 6, y: chart.minY + 3), size: 9, color: .glassTertiary, mono: true)
    }
}
