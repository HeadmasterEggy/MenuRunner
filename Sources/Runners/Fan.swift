import AppKit

extension Runner {
    static let fan = Runner(id: "fan", name: "风扇|Fan", frameCount: 24, size: NSSize(width: 20, height: 20), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        let ring = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 18, height: 18))
        ring.lineWidth = 1.3; ring.stroke()
        for k in 0..<4 {
            let trail: [(Double, Double)] = [[(0.35, 0.22)], [(0.6, 0.12), (0.3, 0.26)], [(0.9, 0.08), (0.6, 0.16), (0.3, 0.3)]][level]
            for (off, a) in trail + [(0.0, 1.0)] {
                ctx.saveGState()
                ctx.translateBy(x: 10, y: 10)
                ctx.rotate(by: CGFloat(-t / 2 * [1, 1.5, 2][level] + Double(k) * .pi / 2 + off))
                let b = NSBezierPath()
                b.move(to: pt(-0.8, 1.6))
                b.curve(to: pt(-0.2, 7.6), controlPoint1: pt(-2.6, 4.2), controlPoint2: pt(-2.4, 7.0))
                b.curve(to: pt(3.8, 5.6), controlPoint1: pt(1.6, 8.6), controlPoint2: pt(3.6, 7.6))
                b.curve(to: pt(0.9, 1.6), controlPoint1: pt(3.6, 4.0), controlPoint2: pt(2.0, 2.4))
                b.close()
                NSColor.black.withAlphaComponent(a).setFill(); b.fill()
                ctx.restoreGState()
            }
        }
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7.6, y: 7.6, width: 4.8, height: 4.8)).fill()
        punch { NSBezierPath(ovalIn: NSRect(x: 9.1, y: 9.1, width: 1.8, height: 1.8)).fill() }
    }
}
