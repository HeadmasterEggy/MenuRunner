import AppKit

extension Runner {
    static let lavaLamp = Runner(id: "lava", name: "熔岩灯|Lava Lamp", frameCount: 48, size: NSSize(width: 14, height: 22), template: false, levels: 3) { t, level in
        func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
        let m = [1.0, 1.5, 2][level]
        let metalHi = c(0.78, 0.80, 0.85), metalLo = c(0.36, 0.37, 0.42)
        let base = NSBezierPath()
        base.move(to: pt(1.2, 0.4)); base.line(to: pt(12.8, 0.4)); base.line(to: pt(10.6, 5.2)); base.line(to: pt(3.4, 5.2)); base.close()
        NSGradient(colors: [metalLo, metalHi, metalLo])!.draw(in: base, angle: 0)
        let cap = NSBezierPath()
        cap.move(to: pt(4.9, 17.6)); cap.line(to: pt(9.1, 17.6)); cap.line(to: pt(8.0, 21.6)); cap.line(to: pt(6.0, 21.6)); cap.close()
        NSGradient(colors: [metalLo, metalHi, metalLo])!.draw(in: cap, angle: 0)
        let glass = NSBezierPath()
        glass.move(to: pt(3.4, 5.0))
        glass.line(to: pt(10.6, 5.0))
        glass.curve(to: pt(9.1, 17.8), controlPoint1: pt(12.6, 9.0), controlPoint2: pt(10.4, 14.0))
        glass.line(to: pt(4.9, 17.8))
        glass.curve(to: pt(3.4, 5.0), controlPoint1: pt(3.6, 14.0), controlPoint2: pt(1.4, 9.0))
        glass.close()
        let glow = [0.0, 0.08, 0.16][level]
        NSGradient(colors: [c(0.90 + glow * 0.5, 0.22 + glow, 0.42), c(0.42, 0.10, 0.52)])!.draw(in: glass, angle: 90)
        NSGraphicsContext.saveGraphicsState()
        glass.addClip()
        let lava = c(1.0, 0.58 + glow, 0.14), lavaHi = c(1.0, 0.86, 0.36)
        var blobs: [(Double, Double, Double)] = []
        let specs: [(Double, Double, Double, Double)] = [(2, 0.0, 1.9, -1.2), (2, 2.4, 1.6, 1.4), (4, 1.1, 1.3, 0.4), (2, 4.2, 1.4, -0.4), (4, 3.3, 1.1, 1.0)]
        for (k, ph, r, dx) in specs.prefix([3, 4, 5][level]) {
            let u = 0.5 - 0.5 * cos(t * k * m + ph)
            let y = 6.2 + u * 9.8, x = 7 + dx + 0.8 * sin(t * k * m * 0.5 * 2 + ph * 1.7)
            blobs.append((x, y, r * (1.05 - 0.25 * u)))
        }
        lava.setFill(); lava.setStroke()
        NSBezierPath(ovalIn: NSRect(x: 2.0, y: 3.6, width: 10, height: 3.4)).fill()
        for i in 0..<blobs.count { for j in (i + 1)..<blobs.count {
            let (x1, y1, r1) = blobs[i], (x2, y2, r2) = blobs[j]
            let d = hypot(x1 - x2, y1 - y2)
            if d < (r1 + r2) * 1.3 {
                let neck = NSBezierPath()
                neck.lineWidth = min(r1, r2) * 1.3 * (1 - max(0, d - (r1 + r2) * 0.8) / ((r1 + r2) * 0.5))
                neck.lineCapStyle = .round
                neck.move(to: pt(x1, y1)); neck.line(to: pt(x2, y2)); neck.stroke()
            }
        } }
        for (x, y, r) in blobs {
            if y - r < 6.6 {
                let neck = NSBezierPath(); neck.lineWidth = r * 1.2; neck.lineCapStyle = .round
                neck.move(to: pt(x, y)); neck.line(to: pt(x, 5.4)); neck.stroke()
            }
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
        }
        lavaHi.setFill()
        for (x, y, r) in blobs { NSBezierPath(ovalIn: NSRect(x: x - r * 0.55, y: y + r * 0.05, width: r * 0.7, height: r * 0.6)).fill() }
        let shine = NSBezierPath()
        shine.lineWidth = 0.7; shine.lineCapStyle = .round
        shine.move(to: pt(4.2, 7.0)); shine.curve(to: pt(5.4, 15.8), controlPoint1: pt(3.4, 10.0), controlPoint2: pt(4.6, 13.6))
        c(1, 1, 1, 0.45).setStroke(); shine.stroke()
        NSGraphicsContext.restoreGraphicsState()
        c(0.22, 0.10, 0.28, 0.9).setStroke()
        glass.lineWidth = 0.6; glass.stroke()
    }
}
