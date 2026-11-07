import AppKit

extension Runner {
    static let clock = Runner(id: "clock", name: "时钟|Clock", frameCount: 48, size: NSSize(width: 20, height: 20), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        let c = pt(10, 10)
        let face = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 18, height: 18))
        face.lineWidth = 1.4; face.stroke()
        for i in 0..<12 {
            let a = Double(i) * .pi / 6, major = i % 3 == 0
            let r0 = major ? 5.9 : 6.7, r1 = 7.6
            ctx.saveGState()
            ctx.setAlpha(major ? 1 : 0.5)
            strokeLine([pt(10 + r0 * cos(a), 10 + r0 * sin(a)), pt(10 + r1 * cos(a), 10 + r1 * sin(a))], major ? 1.2 : 0.8)
            ctx.restoreGState()
        }
        let minuteTurns = [4.0, 6, 8][level], hourTurns = [1.0, 1, 2][level]
        let am = Double.pi / 2 - t * minuteTurns, ah = Double.pi / 2 - t * hourTurns
        let step = 2 * Double.pi * minuteTurns / 48
        let blur = [0, 4, 6][level]
        for i in stride(from: blur, through: 1, by: -1) {
            let a = am + step * 0.85 * Double(i) / Double(blur)
            ctx.saveGState()
            ctx.setAlpha(0.42 * (1 - Double(i) / Double(blur + 1)))
            strokeLine([c, pt(10 + 6.6 * cos(a), 10 + 6.6 * sin(a))], 1.3)
            ctx.restoreGState()
        }
        strokeLine([c, pt(10 + 4.4 * cos(ah), 10 + 4.4 * sin(ah))], 1.9)
        strokeLine([c, pt(10 + 6.6 * cos(am), 10 + 6.6 * sin(am))], 1.3)
        NSBezierPath(ovalIn: NSRect(x: 8.7, y: 8.7, width: 2.6, height: 2.6)).fill()
    }
}
