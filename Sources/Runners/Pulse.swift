import AppKit

extension Runner {
    static let pulse = Runner(id: "pulse", name: "心电图|Heartbeat", frameCount: 45, size: NSSize(width: 30, height: 18), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        let m = [1, 1.5, 2][level]
        let period = 30.0 / Double(level + 1), sx = [1, 0.6, 0.42][level], off = t / (2 * .pi) * 90 * m, base = 5.0
        let beats = Int(3 * m * Double(level + 1))
        let amps = [1.0, 0.8, 0.92, 0.72, 0.97, 0.84, 0.88, 0.76, 0.94]
        let scale = [0.7, 0.9, 1.15][level]
        let keys: [(Double, Double)] = [(0, 0), (4, 0), (5.5, 1.3), (7, 0), (10, 0), (11, -1.3), (12.6, 9.5), (14.2, -3.2),
                                        (15.6, 0), (18, 0), (20, 2.0), (22.5, 0)].map { ($0.0 * sx, $0.1) } + [(period, 0)]
        func ecg(_ x: Double) -> Double {
            let p = x + off, u = p.truncatingRemainder(dividingBy: period)
            let amp = scale * amps[Int(p / period) % beats % amps.count]
            for i in 0..<(keys.count - 1) where u >= keys[i].0 && u <= keys[i + 1].0 {
                let (a, va) = keys[i], (b, vb) = keys[i + 1]
                return base + amp * (va + (vb - va) * (u - a) / (b - a))
            }
            return base
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let line = NSBezierPath()
        line.lineWidth = 1.5; line.lineCapStyle = .round; line.lineJoinStyle = .round
        line.move(to: pt(1.5, ecg(0)))
        for i in 1...104 { let x = Double(i) * 0.25; line.line(to: pt(x + 1.5, ecg(x))) }
        line.stroke()
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        NSGradient(colorsAndLocations: (NSColor.black.withAlphaComponent(0), 0), (NSColor.black, 0.55), (NSColor.black, 1))!
            .draw(in: NSRect(x: 0, y: 0, width: 30, height: 18), angle: 0)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        ctx.endTransparencyLayer()
        let y = min(max(ecg(26), 1.9), 16.1)
        NSBezierPath(ovalIn: NSRect(x: 26.1, y: y - 1.4, width: 2.8, height: 2.8)).fill()
    }
}
