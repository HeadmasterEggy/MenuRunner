import AppKit

extension Runner {
    static let ball = Runner(id: "ball", name: "弹跳球|Bouncing Ball", frameCount: 24, size: NSSize(width: 18, height: 22), levels: 3) { t, level in
        let p = (t / (2 * .pi) * Double([2, 3, 4][level])).truncatingRemainder(dividingBy: 1)
        let h = 4 * p * (1 - p), H = [10.0, 11.4, 12.6][level], r = 3.3, ground = 1.6
        let edge = min(p, 1 - p) / 0.09
        let near = max(0, 1 - edge)
        let v = abs(1 - 2 * p)
        let squash = [0.26, 0.34, 0.42][level] * near
        let stretch = [0.10, 0.16, 0.22][level] * v * min(edge, 1)
        let sy = (1 - squash) * (1 + stretch), sx = (1 + squash) / (1 + stretch * 0.7)
        let cx = 9.0, cy = ground + 0.4 + r * sy + h * H
        let sw = 9.5 * (1 - 0.55 * h) * (1 + squash * 0.5)
        NSColor.black.withAlphaComponent(0.25 + 0.3 * (1 - h)).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - sw / 2, y: ground - 0.9, width: sw, height: 1.8)).fill()
        if level > 0 && v > 0.45 && near == 0 {
            let up = p < 0.5
            let len = (v - 0.3) * [0, 4.5, 6.5][level]
            NSColor.black.withAlphaComponent(0.45).setStroke()
            for dx in [-1.6, 1.6] {
                let y0 = up ? cy - r * sy - 0.8 : cy + r * sy + 0.8
                strokeLine([pt(cx + dx, y0), pt(cx + dx, up ? y0 - len : y0 + len)], 0.9)
            }
            NSColor.black.setStroke()
        }
        NSColor.black.setFill()
        let body = NSBezierPath(ovalIn: NSRect(x: cx - r * sx, y: cy - r * sy, width: 2 * r * sx, height: 2 * r * sy))
        body.fill()
        punch {
            let shine = NSBezierPath()
            shine.lineWidth = 0.9; shine.lineCapStyle = .round
            shine.appendArc(withCenter: pt(cx, cy), radius: r * 0.62, startAngle: 105, endAngle: 165)
            let tr = NSAffineTransform()
            tr.translateX(by: cx, yBy: cy); tr.scaleX(by: sx, yBy: sy); tr.translateX(by: -cx, yBy: -cy)
            shine.transform(using: tr as AffineTransform)
            shine.stroke()
        }
    }
}
