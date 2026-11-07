import AppKit

extension Runner {
    static let radar = Runner(id: "radar", name: "雷达|Radar", frameCount: 48, size: NSSize(width: 20, height: 20), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        let c = pt(10, 10), R = 8.5
        let a = Double.pi / 2 - t * [2, 3, 4][level]
        let ring = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 18, height: 18))
        ring.lineWidth = 1.4; ring.stroke()
        ctx.saveGState()
        ctx.setAlpha(0.3)
        let inner = NSBezierPath(ovalIn: NSRect(x: 5.5, y: 5.5, width: 9, height: 9)); inner.lineWidth = 0.8; inner.stroke()
        strokeLine([pt(10, 2.5), pt(10, 17.5)], 0.6); strokeLine([pt(2.5, 10), pt(17.5, 10)], 0.6)
        ctx.restoreGState()
        let span = [1.1, 1.6, 2.2][level], slices = 28
        for i in 0..<slices {
            let a0 = a + span * Double(i) / Double(slices), a1 = a + span * Double(i + 1) / Double(slices)
            let w = NSBezierPath()
            w.move(to: c)
            w.appendArc(withCenter: c, radius: R, startAngle: CGFloat(a0 * 180 / .pi), endAngle: CGFloat(a1 * 180 / .pi + 0.6))
            w.close()
            NSColor.black.withAlphaComponent(0.6 * pow(1 - Double(i) / Double(slices), 1.6)).setFill(); w.fill()
        }
        NSColor.black.setFill()
        strokeLine([c, pt(10 + R * cos(a), 10 + R * sin(a))], 1.4)
        let blips: [(Double, Double)] = [(5.6, 0.7), (3.4, 2.6), (6.6, 4.1), (4.6, 5.3), (6.0, 2.0)]
        for (r, ang) in blips.prefix([2, 3, 5][level]) {
            var d = (ang - a).truncatingRemainder(dividingBy: 2 * .pi)
            if d < 0 { d += 2 * .pi }
            let v = max(0, 1 - d / 3.6)
            guard v > 0.05 else { continue }
            let s = 1.2 + 1.0 * v
            NSColor.black.withAlphaComponent(0.3 + 0.7 * v).setFill()
            NSBezierPath(ovalIn: NSRect(x: 10 + r * cos(ang) - s / 2, y: 10 + r * sin(ang) - s / 2, width: s, height: s)).fill()
        }
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 8.8, y: 8.8, width: 2.4, height: 2.4)).fill()
    }
}
