import AppKit

extension Runner {
    static let hourglass = Runner(id: "hourglass", name: "沙漏|Hourglass", frameCount: 48, size: NSSize(width: 16, height: 22), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        let p = (t / (2 * .pi) * Double([2, 3, 4][level])).truncatingRemainder(dividingBy: 1)
        let fallEnd = 0.78
        let f = min(p / fallEnd, 1)
        let s = p < fallEnd ? 0 : (p - fallEnd) / (1 - fallEnd)
        let turn = s * s * (3 - 2 * s)
        func bulb(_ w: Double, _ h: Double, _ neck: Double) -> NSBezierPath {
            let b = NSBezierPath()
            b.move(to: pt(-w, h))
            b.line(to: pt(w, h))
            b.curve(to: pt(neck, 0), controlPoint1: pt(w, h * 0.4), controlPoint2: pt(neck, h * 0.3))
            b.curve(to: pt(w, -h), controlPoint1: pt(neck, -h * 0.3), controlPoint2: pt(w, -h * 0.4))
            b.line(to: pt(-w, -h))
            b.curve(to: pt(-neck, 0), controlPoint1: pt(-w, -h * 0.4), controlPoint2: pt(-neck, -h * 0.3))
            b.curve(to: pt(-w, h), controlPoint1: pt(-neck, h * 0.3), controlPoint2: pt(-w, h * 0.4))
            b.close()
            return b
        }
        ctx.translateBy(x: 8, y: 11)
        ctx.rotate(by: CGFloat(-turn * .pi))
        let co = abs(cos(turn * .pi)), si = abs(sin(turn * .pi))
        let fit = min(1, 16 / (14 * co + 21 * si), 22 / (21 * co + 14 * si))
        ctx.scaleBy(x: CGFloat(fit), y: CGFloat(fit))
        for y in [9.6, -9.6] {
            NSBezierPath(roundedRect: NSRect(x: -7, y: y - 1, width: 14, height: 2), xRadius: 1, yRadius: 1).fill()
        }
        let glass = bulb(5.6, 8.6, 1.0)
        glass.lineWidth = 1.4; glass.stroke()
        let inner = 7.2, topLevel = inner * pow(1 - f, 0.6), bottomLevel = -inner + inner * (1 - pow(1 - f, 0.6))
        let mound = 1.6 * sin(.pi * f)
        ctx.saveGState()
        bulb(4.3, inner, 0.5).addClip()
        NSRect(x: -5, y: 0, width: 10, height: topLevel).fill()
        let pile = NSBezierPath()
        pile.move(to: pt(-5, -inner - 0.5)); pile.line(to: pt(5, -inner - 0.5)); pile.line(to: pt(5, bottomLevel))
        pile.line(to: pt(0, bottomLevel + mound)); pile.line(to: pt(-5, bottomLevel)); pile.close()
        pile.fill()
        if s == 0 && f < 0.97 {
            let stream = NSBezierPath()
            stream.lineWidth = [0.8, 1.0, 1.25][level]
            stream.setLineDash([1.1, [0.9, 0.6, 0.35][level]], count: 2, phase: CGFloat(-p * 60))
            stream.move(to: pt(0, 0.6)); stream.line(to: pt(0, bottomLevel + mound))
            stream.stroke()
        }
        ctx.restoreGState()
    }
}
