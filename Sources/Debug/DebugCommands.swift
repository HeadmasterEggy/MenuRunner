import AppKit
import QuartzCore
import IOKit.ps

enum DebugCommand {
    static func stats() {
        let c = CPUMonitor(), nm = NetMonitor(); _ = c.load(); _ = nm.rate()
        Thread.sleep(forTimeInterval: 1)
        let l = c.load(), nr = nm.rate(), m = SystemInfo.memory(), t = TempMonitor().read()
        print(String(format: "CPU %.0f%%  system %.0f%%  user %.0f%%  idle %.0f%%", l.total * 100, l.system * 100, l.user * 100, l.idle * 100))
        print("gpu", GPUMonitor.usage().map(Draw.pct) ?? "nil")
        print("memory", SystemInfo.gb(m.used), "/", SystemInfo.gb(m.total))
        print("storage", SystemInfo.storage().map { "\(SystemInfo.gb($0.used)) / \(SystemInfo.gb($0.total))" } ?? "nil")
        print("battery", SystemInfo.battery().map { "\($0.percent)% \(SystemInfo.stateText($0.state))" } ?? "nil")
        print("battery time", SystemInfo.batteryTime().map { "\($0.label): \($0.value)" } ?? "nil", "estimate", IOPSGetTimeRemainingEstimate())
        print("health", SystemInfo.batteryHealth().map { "\(Draw.pct($0.health)) cycles \($0.cycles)/\($0.designCycles)" } ?? "nil")
        print("temps soc", t.soc.map { String(format: "%.1f", $0) } ?? "nil", "battery", t.battery.map { String(format: "%.1f", $0) } ?? "nil",
              "ssd", t.ssd.map { String(format: "%.1f", $0) } ?? "nil")
        print("network up", NetMonitor.format(nr.up), "down", NetMonitor.format(nr.down))
        for a in ProcessMemory.top(10) { print("  mem", ProcessMemory.format(a.bytes), "×\(a.processes)", a.name) }
        exit(0)
    }

    static func runner(_ r: Runner) {
        let sc: CGFloat = 12, fw = r.size.width * sc, fh = r.size.height * sc
        let sheet = NSImage(size: NSSize(width: fw * CGFloat(r.frameCount), height: fh * 2 * CGFloat(r.levels)), flipped: true) { _ in
            for level in 0..<r.levels {
                let frames = r.frames(level: level)
                for (k, bg) in [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.93, alpha: 1)].enumerated() {
                    let row = level * 2 + k
                    bg.setFill(); NSRect(x: 0, y: CGFloat(row) * fh, width: fw * CGFloat(frames.count), height: fh).fill()
                    NSGraphicsContext.current?.imageInterpolation = .none
                    for (i, img) in frames.enumerated() {
                        img.draw(in: NSRect(x: CGFloat(i) * fw, y: CGFloat(row) * fh, width: fw, height: fh), from: .zero,
                                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    }
                }
            }
            return true
        }
        let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        exit(0)
    }

    static func bench() {
        func bench(_ name: String, _ f: () -> Void) {
            let t0 = CACurrentMediaTime(); for _ in 0..<20 { f() }
            print(String(format: "%-16@ %7.2f ms", name as NSString, (CACurrentMediaTime() - t0) / 20 * 1000))
        }
        let c = CPUMonitor(), n = NetMonitor(), tm = TempMonitor.shared
        bench("cpu") { _ = c.load() }
        bench("gpu") { _ = GPUMonitor.usage() }
        bench("memory") { _ = SystemInfo.memory() }
        bench("storage") { _ = SystemInfo.storage() }
        bench("battery") { _ = SystemInfo.battery() }
        bench("health") { _ = SystemInfo.batteryHealth() }
        bench("batteryTime") { _ = SystemInfo.batteryTime() }
        bench("temps") { _ = tm.read() }
        bench("network") { _ = n.rate() }
        bench("pressure") { _ = SystemInfo.memoryPressure() }
        let frames = Runner.coffee.frames()
        bench("coffee frames") { _ = Runner.coffee.frames() }
        _ = frames
        exit(0)
    }

    static func icon() {
        let dir = CommandLine.arguments[2]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sprite = Runner.rocketCat.frames()[1]
        func render(_ px: Int) -> Data {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: px, height: px)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let k = CGFloat(px) / 1024
            let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
            let shape = NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 24 * k; shadow.shadowOffset = NSSize(width: 0, height: -10 * k); shadow.set()
            NSColor.black.setFill(); shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            shape.addClip()
            NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.22, blue: 0.62, alpha: 1),
                                NSColor(srgbRed: 0.10, green: 0.12, blue: 0.32, alpha: 1)])!.draw(in: body, angle: -90)
            NSGradient(colors: [NSColor(srgbRed: 1, green: 0.62, blue: 0.30, alpha: 0.30), NSColor(srgbRed: 1, green: 0.62, blue: 0.30, alpha: 0)])!
                .draw(fromCenter: NSPoint(x: 540 * k, y: 500 * k), radius: 0, toCenter: NSPoint(x: 540 * k, y: 500 * k), radius: 380 * k, options: [])
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(190, 780, 10), (300, 860, 6), (760, 830, 9), (850, 700, 6), (230, 300, 7),
                                                        (820, 250, 10), (640, 860, 5), (150, 560, 5), (880, 470, 5), (420, 190, 6)]
            for (x, y, r) in stars {
                NSColor(srgbRed: 1, green: 0.93, blue: 0.75, alpha: 0.9).setFill()
                if r >= 9 {
                    NSRect(x: (x - r * 1.6) * k, y: (y - r * 0.35) * k, width: r * 3.2 * k, height: r * 0.7 * k).fill()
                    NSRect(x: (x - r * 0.35) * k, y: (y - r * 1.6) * k, width: r * 0.7 * k, height: r * 3.2 * k).fill()
                } else {
                    NSBezierPath(ovalIn: NSRect(x: (x - r / 2) * k, y: (y - r / 2) * k, width: r * k, height: r * k)).fill()
                }
            }
            NSGraphicsContext.current?.imageInterpolation = .none
            let sw: CGFloat = 36 * 21 * k, sh: CGFloat = 20 * 21 * k
            let dst = NSRect(x: 512 * k - sw / 2, y: 505 * k - sh / 2, width: sw, height: sh)
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow(); glow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            glow.shadowBlurRadius = 18 * k; glow.shadowOffset = NSSize(width: 0, height: -14 * k); glow.set()
            sprite.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.restoreGraphicsState()
            return rep.representation(using: .png, properties: [:])!
        }
        for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                           ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
            try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
        }
        exit(0)
    }

    static func preview() {
        let maxFrames = 15
        let sc = 8.0, w = Runner.all.map { $0.size.width * CGFloat(min($0.frameCount, maxFrames)) }.max()!
        let rowH = 22.0, rows = Double(Runner.all.count)
        let sheet = NSImage(size: NSSize(width: w * sc, height: rowH * sc * rows), flipped: true) { _ in
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w * sc, height: rowH * sc * rows).fill()
            for (row, r) in Runner.all.enumerated() {
                for (i, f) in r.frames().prefix(maxFrames).enumerated() {
                    f.draw(in: NSRect(x: Double(i) * r.size.width * sc, y: Double(row) * rowH * sc, width: r.size.width * sc, height: r.size.height * sc),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            return true
        }
        let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        exit(0)
    }

    static func render() {
        _ = NSApplication.shared
        let model = StatsModel(), cpu = CPUMonitor(), net = NetMonitor()
        _ = cpu.load(); _ = net.rate(); Thread.sleep(forTimeInterval: 0.6)
        for _ in 0..<3 {
            model.update(cpu: cpu.load(), gpu: GPUMonitor.usage(), memory: SystemInfo.memory(), storage: SystemInfo.storage(),
                         battery: SystemInfo.battery(), health: SystemInfo.batteryHealth(), temps: TempMonitor.shared.read(), net: net.rate())
            Thread.sleep(forTimeInterval: 0.3)
        }
        model.tick(dt: 10)
        let panel = PanelController(model: model)
        panel.updateBatteryTime()
        panel.memoryPressure = SystemInfo.memoryPressure()
        panel.gpuMemory = GPUMonitor.memoryInUse()
        panel.netTotals = (net.totalUp, net.totalDown)
        panel.detail.refresh(.cpu, wait: true); Thread.sleep(forTimeInterval: 0.8); panel.detail.refresh(.cpu, wait: true)
        let v = panel.debugMainView, sz = v.frame.size
        let sheet = NSImage(size: NSSize(width: sz.width * 2 + 20, height: sz.height), flipped: false) { _ in
            for (i, name) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
                let ox = CGFloat(i) * (sz.width + 20)
                NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                    (i == 0 ? NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.93, alpha: 1) : NSColor(white: 0.12, alpha: 1)).setFill()
                    NSRect(x: ox, y: 0, width: sz.width, height: sz.height).fill()
                    for f in panel.debugCardFrames {
                        (i == 0 ? NSColor.white.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.08)).setFill()
                        NSBezierPath(roundedRect: f.offsetBy(dx: ox, dy: 0), xRadius: 18, yRadius: 18).fill()
                    }
                }
                v.appearance = NSAppearance(named: name)
                let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
                v.cacheDisplay(in: v.bounds, to: rep)
                rep.draw(in: NSRect(x: ox, y: 0, width: sz.width, height: sz.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            return true
        }
        let out = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        exit(0)
    }
}
