import AppKit

extension Runner {
    static let dna = Runner(id: "dna", name: "DNA 双螺旋|DNA Helix", frameCount: 24, size: NSSize(width: 26, height: 18), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        let ph = t * [1, 1.5, 2][level], k = 2 * Double.pi / 16, amp = [5.0, 5.8, 6.6][level], cy = 9.0
        func y(_ x: Double, _ s: Double) -> Double { cy + amp * sin(k * x + ph + s * .pi) }
        func z(_ x: Double, _ s: Double) -> Double { cos(k * x + ph + s * .pi) }
        func strands(front: Bool) -> NSBezierPath {
            let path = NSBezierPath()
            for s in [0.0, 1.0] {
                var open = false
                for i in 0...100 {
                    let x = 0.5 + Double(i) * 0.25
                    if (z(x, s) >= 0) == front {
                        if open { path.line(to: pt(x, y(x, s))) } else { path.move(to: pt(x, y(x, s))); open = true }
                    } else { open = false }
                }
            }
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            return path
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setAlpha(0.4)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let back = strands(front: false); back.lineWidth = 1.3; back.stroke()
        ctx.endTransparencyLayer()
        ctx.setAlpha(0.65)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let rungs = [7, 9, 11][level], gap = 26.0 / Double(rungs)
        for j in 0..<rungs {
            let x = gap / 2 + Double(j) * gap, a = y(x, 0), b = y(x, 1)
            if abs(a - b) > 1.2 { strokeLine([pt(x, a), pt(x, b)], 1.0) }
        }
        ctx.endTransparencyLayer()
        ctx.setAlpha(1)
        let front = strands(front: true); front.lineWidth = 1.9; front.stroke()
        if level == 2 {
            for j in 0..<rungs {
                let x = gap / 2 + Double(j) * gap
                for s in [0.0, 1.0] where z(x, s) > 0.3 {
                    NSBezierPath(ovalIn: NSRect(x: x - 1.3, y: y(x, s) - 1.3, width: 2.6, height: 2.6)).fill()
                }
            }
        }
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        NSGradient(colorsAndLocations: (NSColor.black.withAlphaComponent(0), 0), (NSColor.black, 0.16), (NSColor.black, 0.84),
                   (NSColor.black.withAlphaComponent(0), 1))!.draw(in: NSRect(x: 0, y: 0, width: 26, height: 18), angle: 0)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        ctx.endTransparencyLayer()
    }
}
