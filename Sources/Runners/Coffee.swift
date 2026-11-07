import AppKit

extension Runner {
    static let coffee = Runner(id: "coffee", name: "咖啡|Coffee", frameCount: 24, size: NSSize(width: 22, height: 22), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: 0.5, y: 0)

        let K = 1.4, ax = 9.5
        ctx.saveGState()
        ctx.translateBy(x: ax, y: 0); ctx.scaleBy(x: K, y: K); ctx.translateBy(x: -ax, y: 0)

        let cup = NSBezierPath()
        cup.move(to: NSPoint(x: 3.2, y: 9.6))
        cup.line(to: NSPoint(x: 14.8, y: 9.6))
        cup.curve(to: NSPoint(x: 9.0, y: 0.6), controlPoint1: NSPoint(x: 15.0, y: 3.0), controlPoint2: NSPoint(x: 14.0, y: 0.6))
        cup.curve(to: NSPoint(x: 3.2, y: 9.6), controlPoint1: NSPoint(x: 4.0, y: 0.6), controlPoint2: NSPoint(x: 3.0, y: 3.0))
        cup.fill()
        NSBezierPath(roundedRect: NSRect(x: 2.6, y: 9.0, width: 12.8, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()
        let handle = NSBezierPath(ovalIn: NSRect(x: 12.6, y: 3.8, width: 4.2, height: 4.2))
        handle.lineWidth = 1.4; handle.stroke()

        let surface = NSBezierPath(ovalIn: NSRect(x: 3.7, y: 9.3, width: 10.6, height: 0.8))
        punch { surface.fill() }
        NSColor.black.withAlphaComponent(0.45).setFill(); surface.fill(); NSColor.black.setFill()

        punch {
            let shine = NSBezierPath()
            shine.lineWidth = 0.8; shine.lineCapStyle = .round
            shine.move(to: NSPoint(x: 5.0, y: 8.0))
            shine.curve(to: NSPoint(x: 6.6, y: 3.0), controlPoint1: NSPoint(x: 4.6, y: 6.2), controlPoint2: NSPoint(x: 5.2, y: 4.1))
            shine.stroke()
        }
        ctx.restoreGState()

        let left = ax + (3.6 - ax) * K, right = ax + (14.4 - ax) * K
        let mid = (left + right) / 2, amp = (right - left) / 2 - 2.2
        let base = 10.4 * K + 0.6, top = [17.5, 20.6, 21.6][level]
        let n = 40, tt = t * [2, 3, 4][level]
        func wisp(_ dx: Double, _ ph: Double, _ ws: Double, _ topY: Double) -> NSBezierPath {
            let path = NSBezierPath()
            for i in 0...n {
                let u = Double(i) / Double(n)
                let x = mid + dx * (1 - u * 0.5) + sin(u * 1.25 * .pi - tt + ph) * (amp + 1) * ws * pow(u, 1.1), y = base + u * (topY - base)
                let w = ((right - left - 1.0) * pow(1 - u, 2.2) + 1.8) * ws, h = 1.2 + u * 0.4
                path.append(NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h)))
            }
            return path
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let steam = wisp(0, 0, 1, top)
        if level == 2 { steam.append(wisp(-4.2, .pi, 0.45, top - 2)); steam.append(wisp(4.2, .pi / 2, 0.45, top - 3)) }
        ctx.saveGState()
        NSBezierPath(rect: NSRect(x: -1, y: base, width: 24, height: 22)).addClip()
        steam.fill()
        ctx.restoreGState()
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        let alpha = [0.4, 0.6, 0.8][level]
        NSGradient(starting: NSColor.black.withAlphaComponent(alpha), ending: NSColor.black.withAlphaComponent(alpha / 2))!
            .draw(in: NSRect(x: -1, y: base - 2, width: 24, height: 24 - base), angle: 90)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        ctx.endTransparencyLayer()
    }
}
