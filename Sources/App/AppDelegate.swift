import AppKit
import QuartzCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let sampler = Sampler()
    private let model = StatsModel()
    private lazy var panel = PanelController(model: model)
    private var runner = Runner.all.first { $0.id == UserDefaults.standard.string(forKey: "runner") } ?? Runner.coffee
    private lazy var frames = runner.frames(appearance: statusItem.button?.effectiveAppearance)
    private var appearanceObservation: NSKeyValueObservation?
    private var lastDark: Bool?
    private var frameIndex = 0
    private var animTimer: Timer?
    private var sampleTimer: Timer?
    private var usage = 0.0
    private var runLevel = 0

    private var barMetric = UserDefaults.standard.string(forKey: "barMetric") ?? "none"
    private static var barOptions: [(String, String)] {
        [("cpu", "CPU"), ("gpu", "GPU"), ("memory", L("内存", "Memory")), ("battery", L("电池", "Battery")),
         ("network", L("网络", "Network")), ("temp", L("芯片温度", "SoC Temperature")),
         ("batTemp", L("电池温度", "Battery Temperature"))]
            + (FanMonitor.shared.hasFans ? [("fan", L("风扇转速", "Fan Speed"))] : [])
            + [("none", L("不显示", "None"))]
    }
    private static var styleOptions: [(String, String)] {
        [("graph+text", L("图表 + 数字", "Graph + Number")), ("graph", L("仅图表", "Graph Only")), ("text", L("仅数字", "Number Only"))]
    }
    private var barStyle = UserDefaults.standard.string(forKey: "barStyle") ?? "graph+text"
    private static let langOptions = [("system", "跟随系统 / System"), ("zh", "中文"), ("en", "English")]
    private let settingsMenu = NSMenu()
    private let visibility = StatusVisibility()
    private var targetFps: Double = 0
    private var widthKey = ""
    private var widthFloor: CGFloat = 0
    private let updateItem = NSMenuItem()
    private let autoUpdateItem = NSMenuItem()

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(size: frames[0].size)
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        buildSettingsMenu()
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] b, _ in
            guard let self else { return }
            let dark = b.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            guard dark != self.lastDark else { return }
            self.lastDark = dark
            self.frames = self.runner.frames(appearance: b.effectiveAppearance, level: self.runLevel)
            self.installRunAnimation()
        }
        installRunAnimation()
        visibility.onChange = { [weak self] visible in
            guard let self else { return }
            self.setRunSpeed(visible ? self.targetFps : 0, force: true)
            if visible { self.sample() }
        }
        visibility.watch(button.window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.panel.detail.prewarmStorage() }
        panel.onSettings = { [weak self] _ in self?.showSettings() }

        panel.onVisibilityChange = { [weak self] open in
            guard let self else { return }
            self.panelOpen = open
            self.startSampling(interval: open ? self.refreshInterval : max(self.refreshInterval, 1.5))
        }
        MachineSpec.loadModelName { [weak self] name in self?.panel.spec.model = name }
        sampleQueue.async { [sampler] in sampler.prime() }
        startSampling(interval: 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.sample() }
        scheduleAnimation()
        Updater.shared.onChange = { [weak self] in self?.refreshUpdateItems() }
        Updater.shared.start()
        if CommandLine.arguments.contains("--check-update") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Updater.shared.checkNow() }
        }

        if CommandLine.arguments.contains("--settings-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showSettings() }
        }
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.popSettings(from: button) }
        }
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.panel.show(below: button)
                NSLog("panel debug: shown=%d", self.panel.isVisible ? 1 : 0)
                if let i = CommandLine.arguments.firstIndex(of: "--detail"), i + 1 < CommandLine.arguments.count {
                    let map: [String: DetailKind] = ["system": .system, "cpu": .cpu, "gpu": .gpu, "memory": .memory, "temps": .temps,
                                                     "storage": .storage, "battery": .battery, "network": .network]
                    if let k = map[CommandLine.arguments[i + 1]] { self.panel.debugShow(k) }
                    if CommandLine.arguments[i + 1] == "settings" { self.showSettings() }
                }
            }
        }
    }

    func applicationWillTerminate(_ n: Notification) { panel.detail.stopNetwork() }

    private func startSampling(interval: Double) {
        StatsModel.interval = interval
        sampleTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        sampleTimer = t
    }

    private var speedSource = UserDefaults.standard.string(forKey: "speedSource") ?? "cpu"
    private var refreshInterval: Double = {
        let v = UserDefaults.standard.double(forKey: "refreshInterval"); return v > 0 ? v : 0.5
    }()
    private var panelOpen = false
    private var submenus: [String: NSMenu] = [:]

    private func icon(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    private func choiceMenu(_ key: String, _ title: String, _ symbol: String, _ options: [(String, String)], current: String) -> NSMenuItem {
        let sub = NSMenu()
        for (id, name) in options {
            let item = NSMenuItem(title: name, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [key, id]
            item.state = id == current ? .on : .off
            sub.addItem(item)
        }
        submenus[key] = sub
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = icon(symbol)
        item.submenu = sub
        return item
    }

    @MainActor private func buildSettingsMenu() {
        settingsMenu.removeAllItems()
        let open = NSMenuItem(title: L("设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        open.target = self; open.image = icon("gearshape")
        settingsMenu.addItem(open)
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(NSMenuItem.sectionHeader(title: L("外观", "Appearance")))
        settingsMenu.addItem(choiceMenu("runner", "Runner", "figure.run",
            Runner.all.map { ($0.id, $0.displayName) }, current: runner.id))
        settingsMenu.addItem(choiceMenu("barMetric", L("菜单栏显示", "Menu Bar Shows"), "menubar.rectangle", Self.barOptions, current: barMetric))
        settingsMenu.addItem(choiceMenu("barStyle", L("菜单栏样式", "Menu Bar Style"), "chart.xyaxis.line", Self.styleOptions, current: barStyle))
        settingsMenu.addItem(choiceMenu("speedSource", L("Runner 速度跟随", "Runner Speed Follows"), "speedometer",
            [("cpu", "CPU"), ("gpu", "GPU"), ("memory", L("内存", "Memory"))], current: speedSource))

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(NSMenuItem.sectionHeader(title: L("数据", "Data")))
        settingsMenu.addItem(choiceMenu("refreshInterval", L("刷新频率", "Refresh Rate"), "arrow.clockwise",
            [("0.5", L("实时（0.5 秒）", "Real-time (0.5s)")), ("1.0", L("标准（1 秒）", "Standard (1s)")), ("2.0", L("省电（2 秒）", "Power Saving (2s)"))],
            current: String(format: "%.1f", refreshInterval)))
        settingsMenu.addItem(choiceMenu("tempUnit", L("温度单位", "Temperature Unit"), "thermometer.medium",
            [("C", L("摄氏度 °C", "Celsius °C")), ("F", L("华氏度 °F", "Fahrenheit °F"))], current: TempUnit.fahrenheit ? "F" : "C"))
        settingsMenu.addItem(choiceMenu("lang", "语言 / Language", "globe", Self.langOptions, current: Lang.mode))

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(NSMenuItem.sectionHeader(title: L("系统", "System")))
        if UserDefaults.standard.object(forKey: "didSetupLogin") == nil {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
        }
        let loginItem = NSMenuItem(title: L("开机自动启动", "Launch at Login"), action: #selector(toggleLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.image = icon("power")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settingsMenu.addItem(loginItem)
        let am = NSMenuItem(title: L("打开活动监视器", "Open Activity Monitor"), action: #selector(openActivityMonitor), keyEquivalent: "a")
        am.target = self; am.image = icon("waveform.path.ecg")
        settingsMenu.addItem(am)
        let about = NSMenuItem(title: L("关于 MenuRunner", "About MenuRunner"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self; about.image = icon("info.circle")
        settingsMenu.addItem(about)
        updateItem.action = #selector(checkForUpdates)
        updateItem.target = self; updateItem.image = icon("arrow.down.circle")
        settingsMenu.addItem(updateItem)
        autoUpdateItem.title = L("自动更新", "Automatically Update")
        autoUpdateItem.action = #selector(toggleAutoUpdate)
        autoUpdateItem.target = self; autoUpdateItem.image = icon("arrow.triangle.2.circlepath")
        settingsMenu.addItem(autoUpdateItem)
        refreshUpdateItems()

        settingsMenu.addItem(.separator())
        let quit = NSMenuItem(title: L("退出", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = icon("xmark.circle")
        settingsMenu.addItem(quit)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        apply(pair[0], pair[1])
    }

    private func apply(_ key: String, _ id: String) {
        submenus[key]?.items.forEach { $0.state = (($0.representedObject as? [String])?.last == id) ? .on : .off }
        if settingsModel.values[key] != id { settingsModel.values[key] = id }
        switch key {
        case "runner":
            guard let r = Runner.all.first(where: { $0.id == id }) else { return }
            runner = r; runLevel = min(Int(min(max(usage, 0), 1) * Double(r.levels)), r.levels - 1)
            frames = r.frames(appearance: statusItem.button?.effectiveAppearance, level: runLevel); frameIndex = 0
            UserDefaults.standard.set(id, forKey: "runner")
            updateStatusImage()
            installRunAnimation()
        case "barMetric":
            barMetric = id; UserDefaults.standard.set(id, forKey: "barMetric"); sample()
        case "barStyle":
            barStyle = id; UserDefaults.standard.set(id, forKey: "barStyle"); sample()
        case "speedSource":
            speedSource = id; UserDefaults.standard.set(id, forKey: "speedSource"); sample()
        case "refreshInterval":
            refreshInterval = Double(id) ?? 0.5
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            startSampling(interval: panelOpen ? refreshInterval : max(refreshInterval, 1.5))
        case "tempUnit":
            TempUnit.fahrenheit = id == "F"; sample(); panel.redrawAll()
        case "lang":
            Lang.mode = id; buildSettingsMenu(); panel.redrawAll(); sample()
            settingsModel.langTick += 1
        default: break
        }
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MenuRunner",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            .credits: NSAttributedString(string: L("菜单栏里的小跑者 + 系统监控", "A tiny menu bar runner + system monitor"),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.hide()
            popSettings(from: sender)
        } else if panel.isVisible {
            panel.hide()
        } else {
            panel.show(below: sender)
        }
    }

    private lazy var settingsModel: SettingsModel = {
        let m = SettingsModel(values: [
            "runner": runner.id, "barMetric": barMetric, "barStyle": barStyle, "speedSource": speedSource,
            "refreshInterval": String(format: "%.1f", refreshInterval), "tempUnit": TempUnit.fahrenheit ? "F" : "C", "lang": Lang.mode,
        ], login: SMAppService.mainApp.status == .enabled)
        m.apply = { [weak self] k, v in self?.apply(k, v) }
        m.options = { key in
            switch key {
            case "barMetric": return Self.barOptions.map { ($0.0, $0.1) }
            case "barStyle": return Self.styleOptions.map { ($0.0, $0.1) }
            case "speedSource": return [("cpu", "CPU"), ("gpu", "GPU"), ("memory", L("内存", "Memory"))]
            case "refreshInterval": return [("0.5", L("0.5 秒", "0.5s")), ("1.0", L("1 秒", "1s")), ("2.0", L("2 秒", "2s"))]
            case "tempUnit": return [("C", "°C"), ("F", "°F")]
            case "lang": return Self.langOptions.map { ($0.0, $0.1) }
            default: return []
            }
        }
        m.setLogin = { [weak self] on in
            let svc = SMAppService.mainApp
            do { if on { try svc.register() } else { try svc.unregister() } } catch { NSLog("Login item error: \(error)") }
            if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            self?.buildSettingsMenu()
            return svc.status == .enabled
        }
        m.openActivityMonitor = { [weak self] in self?.openActivityMonitor() }
        return m
    }()
    @objc private func showSettings() {
        panel.settingsModel = settingsModel
        if !panel.isVisible, let button = statusItem.button { panel.show(below: button) }
        settingsModel.login = SMAppService.mainApp.status == .enabled
        panel.showSettings()
    }

    private func popSettings(from view: NSView) {
        settingsMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    private var sampling = false

    private func sample() {
        guard !sampling else { return }
        sampling = true
        let needTemps = panel.isVisible || barMetric == "temp" || barMetric == "batTemp"
        let needFans = FanMonitor.shared.hasFans && (panel.isVisible || barMetric == "fan")
        let panelVisible = panel.isVisible
        let sampler = self.sampler
        sampleQueue.async { [weak self] in
            let s = sampler.collect(needTemps: needTemps, needFans: needFans, panelVisible: panelVisible)
            DispatchQueue.main.async { self?.sampling = false; self?.apply(s) }
        }
    }

    private func apply(_ s: Sample) {
        let l = s.load, g = s.gpu, m = s.memory, n = s.net, t = s.temps, bat = s.battery
        switch speedSource {
        case "gpu":    usage = g ?? 0
        case "memory": usage = m.used / m.total
        default:       usage = l.total
        }
        panel.setBatteryTime(s.batteryTime)
        panel.sampleMain(pressure: s.pressure)
        model.update(cpu: l, gpu: g, memory: m, storage: s.storage, battery: bat,
                     health: s.health, temps: t, net: n, fans: s.fans)
        let pct = Draw.pct
        let title: String
        switch barMetric {
        case "gpu":     title = " " + (g.map(pct) ?? "--")
        case "memory":  title = " " + pct(m.used / m.total)
        case "battery": title = bat.map { " \($0.percent)%" } ?? " --"
        case "network": title = " ↓\(NetMonitor.format(n.down, compact: true)) ↑\(NetMonitor.format(n.up, compact: true))"
        case "temp":    title = t.soc.map { " " + TempUnit.format($0, decimals: 0, unit: false) } ?? " --"
        case "batTemp": title = t.battery.map { " " + TempUnit.format($0, decimals: 1, unit: false) } ?? " --"
        case "fan":     title = FanMonitor.average(s.fans).map { " " + FanMonitor.format($0, unit: false) } ?? " --"
        case "none":    title = ""
        default:        title = " " + pct(l.total)
        }
        guard visibility.visible || panel.isVisible else { return }
        setStatusTitle(barStyle == "graph" ? "" : title)
        var tip = ["CPU " + pct(l.total), L("内存 ", "Memory ") + pct(m.used / m.total)]
        if let g { tip.append("GPU " + pct(g)) }
        if let soc = t.soc { tip.append(L("温度 ", "Temp ") + TempUnit.format(soc, decimals: 0)) }
        if let bat { tip.append(L("电池 ", "Battery ") + "\(bat.percent)%") }
        if let rpm = FanMonitor.average(s.fans) { tip.append(L("风扇 ", "Fan ") + FanMonitor.format(rpm)) }
        let tipText = tip.joined(separator: " · ")
        if statusItem.button?.toolTip != tipText { statusItem.button?.toolTip = tipText }
        if panel.isVisible {
            if let gm = s.gpuMemory { panel.gpuMemory = gm }
            panel.netTotals = s.netTotals
        }
        updateStatusImage()
        scheduleAnimation()
    }

    private func setStatusTitle(_ title: String) {
        guard let b = statusItem.button else { return }
        if b.title != title { b.title = title }
        let key = runner.id + barMetric + barStyle
        if key != widthKey {
            widthKey = key; widthFloor = 0
            statusItem.length = NSStatusItem.variableLength
        }
        let w = ceil(b.fittingSize.width)
        if w > widthFloor { widthFloor = w; statusItem.length = w }
    }

    private func updateStatusImage() {
        let rf = frames[frameIndex]
        let placeholder = NSImage(size: rf.size)
        guard barStyle != "text", barMetric != "none" else {
            statusItem.button?.image = placeholder; refreshWidth(); layoutRunLayer(); return
        }
        let gw: CGFloat
        switch barMetric {
        case "battery": gw = 22
        case "temp", "batTemp": gw = 9
        default: gw = 26
        }
        let h = max(rf.size.height, 18)
        let size = NSSize(width: rf.size.width + 4 + gw, height: h)
        let img = NSImage(size: size, flipped: false) { [weak self] _ in
            self?.drawMini(in: NSRect(x: rf.size.width + 4, y: (h - 14) / 2, width: gw, height: 14))
            return true
        }
        img.isTemplate = true
        statusItem.button?.image = img
        refreshWidth()
        layoutRunLayer()
    }

    private func refreshWidth() {
        setStatusTitle(statusItem.button?.title ?? "")
    }

    private let runLayer = CALayer()
    private var runFps: Double = 0

    private func cgFrames() -> [CGImage] {
        let appearance = statusItem.button?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return frames.compactMap { img in
            let scale: CGFloat = 2, size = img.size
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .none
            img.draw(in: NSRect(origin: .zero, size: size))
            if runner.template {
                appearance.performAsCurrentDrawingAppearance {
                    NSColor.labelColor.setFill()
                    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            return rep.cgImage
        }
    }

    private func installRunAnimation() {
        guard let button = statusItem.button else { return }
        if runLayer.superlayer == nil {
            button.wantsLayer = true
            runLayer.magnificationFilter = .nearest
            runLayer.contentsGravity = .resize
            button.layer?.addSublayer(runLayer)
        }
        let cg = cgFrames()
        guard !cg.isEmpty else { return }
        runLayer.removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        runLayer.contents = cg[0]
        CATransaction.commit()
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = cg
        anim.calculationMode = .discrete
        anim.duration = Double(cg.count)
        anim.repeatCount = .infinity
        runLayer.beginTime = 0; runLayer.timeOffset = 0
        runLayer.add(anim, forKey: "run")
        setRunSpeed(visibility.visible ? targetFps : 0, force: true)
        layoutRunLayer()
    }

    private func setRunSpeed(_ fps: Double, force: Bool = false) {
        guard force || abs(fps - runFps) > 0.05 else { return }
        runFps = fps
        let now = CACurrentMediaTime()
        let local = runLayer.convertTime(now, from: nil)
        runLayer.speed = Float(fps)
        runLayer.timeOffset = local
        runLayer.beginTime = now
    }

    private func layoutRunLayer() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let b = self.statusItem.button, let cell = b.cell as? NSButtonCell else { return }
            let r = cell.imageRect(forBounds: b.bounds)
            let size = self.frames.first?.size ?? .zero
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.runLayer.frame = CGRect(x: r.minX, y: r.midY - size.height / 2, width: size.width, height: size.height)
            CATransaction.commit()
        }
    }

    private func drawMini(in r: NSRect) {
        let m = model
        NSColor.black.setFill(); NSColor.black.setStroke()
        func spark(_ values: [Double], line: [Double]? = nil) {
            let frame = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            frame.lineWidth = 1
            NSColor.black.withAlphaComponent(0.45).setStroke(); frame.stroke()
            let inner = r.insetBy(dx: 1.5, dy: 1.5)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: inner, xRadius: 1.5, yRadius: 1.5).addClip()
            let n = 24, step = inner.width / CGFloat(n - 2)
            let shift = step * CGFloat(1 - m.scroll)
            func path(_ v: [Double]) -> NSBezierPath {
                let vs = Array(v.suffix(n))
                let p = NSBezierPath()
                for (i, x) in vs.enumerated() {
                    let pt = NSPoint(x: inner.maxX - step * CGFloat(vs.count - 1 - i) + shift,
                                     y: inner.minY + inner.height * CGFloat(min(max(x, 0), 1)))
                    i == 0 ? p.move(to: pt) : p.line(to: pt)
                }
                return p
            }
            guard values.count >= 2 else { NSGraphicsContext.restoreGraphicsState(); return }
            let area = path(values)
            area.line(to: NSPoint(x: inner.maxX + step, y: inner.minY))
            area.line(to: NSPoint(x: inner.minX - step * 2, y: inner.minY))
            area.close()
            NSColor.black.withAlphaComponent(line == nil ? 1 : 0.55).setFill(); area.fill()
            if let line, line.count >= 2 {
                let l = path(line); l.lineWidth = 1.2; l.lineJoinStyle = .round
                NSColor.black.setStroke(); l.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        func thermo(_ c: Double?) {
            let tube = NSRect(x: r.midX - 2, y: r.minY + 3, width: 4, height: r.height - 3)
            let outline = NSBezierPath(roundedRect: tube, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1; outline.stroke()
            NSBezierPath(ovalIn: NSRect(x: r.midX - 3.5, y: r.minY, width: 7, height: 7)).fill()
            let f = CGFloat(min(max(((c ?? 20) - 20) / 80, 0), 1))
            NSRect(x: tube.minX + 1, y: tube.minY, width: tube.width - 2, height: (tube.height - 1) * f).fill()
        }
        switch barMetric {
        case "gpu":    spark(m.gpuHistory)
        case "memory": spark(m.memHistory)
        case "fan":    spark(m.fanHistory)
        case "network":
            let peak = max(m.netHistory.suffix(24).map { max($0.up, $0.down) }.max() ?? 0, 10 * 1024)
            spark(m.netHistory.map { $0.down / peak }, line: m.netHistory.map { $0.up / peak })
        case "battery":
            let body = NSRect(x: r.minX, y: r.midY - 5, width: r.width - 3, height: 10)
            let o = NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            o.lineWidth = 1; o.stroke()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.5, y: r.midY - 2, width: 1.8, height: 4), xRadius: 0.8, yRadius: 0.8).fill()
            let f = CGFloat(Double(m.battery?.percent ?? 0) / 100)
            NSBezierPath(roundedRect: NSRect(x: body.minX + 2, y: body.minY + 2, width: (body.width - 4) * f, height: body.height - 4),
                         xRadius: 1.2, yRadius: 1.2).fill()
            if m.battery?.state == "charging" {
                NSGraphicsContext.current?.compositingOperation = .clear
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: body.midX + 1, y: body.maxY - 1)); bolt.line(to: NSPoint(x: body.midX - 2.5, y: body.midY - 0.5))
                bolt.line(to: NSPoint(x: body.midX, y: body.midY - 0.5)); bolt.line(to: NSPoint(x: body.midX - 1, y: body.minY + 1))
                bolt.line(to: NSPoint(x: body.midX + 2.5, y: body.midY + 0.5)); bolt.line(to: NSPoint(x: body.midX, y: body.midY + 0.5))
                bolt.close(); bolt.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }
        case "temp":    thermo(m.temps.soc)
        case "batTemp": thermo(m.temps.battery)
        default:        spark(m.cpuHistory.map { $0.total })
        }
    }

    private func scheduleAnimation() {
        let u = min(max(usage, 0), 1)
        let fps = u <= 0.5 ? 4 * pow(4, u * 2) : 16 * pow(25.0 / 16, u * 2 - 1)
        let raw = u * Double(runner.levels)
        if runner.levels > 1, abs(raw - (Double(runLevel) + 0.5)) > 0.6 {
            runLevel = min(Int(raw), runner.levels - 1)
            frames = runner.frames(appearance: statusItem.button?.effectiveAppearance, level: runLevel)
            installRunAnimation()
        }
        let interval = 1 / fps
        if CommandLine.arguments.contains("--fps-log") { NSLog("fps debug: usage=%.0f%% fps=%.1f", u * 100, fps) }
        _ = interval
        targetFps = fps
        setRunSpeed(visibility.visible || panel.isVisible ? fps : 0)
    }

    @MainActor @objc private func checkForUpdates() {
        if case .available = Updater.shared.phase { Updater.shared.installPending() } else { Updater.shared.checkNow() }
    }

    @MainActor @objc private func toggleAutoUpdate() { Updater.shared.autoUpdate.toggle() }

    @MainActor private func refreshUpdateItems() {
        let updater = Updater.shared
        switch updater.phase {
        case .available(let v): updateItem.title = L("更新到 \(v)", "Update to \(v)")
        case .checking: updateItem.title = L("正在检查更新…", "Checking for Updates…")
        case .downloading(let v): updateItem.title = L("正在下载 \(v)…", "Downloading \(v)…")
        default: updateItem.title = L("检查更新…", "Check for Updates…")
        }
        autoUpdateItem.state = updater.autoUpdate ? .on : .off
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let svc = SMAppService.mainApp
        do { if svc.status == .enabled { try svc.unregister() } else { try svc.register() } }
        catch { NSLog("Login item error: \(error)") }
        if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        sender.state = svc.status == .enabled ? .on : .off
    }
}
