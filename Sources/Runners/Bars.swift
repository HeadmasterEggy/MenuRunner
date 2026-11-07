import AppKit

extension Runner {
    static let bars = Runner(id: "bars", name: "音波|Sound Wave", frameCount: 24, size: NSSize(width: 22, height: 18), levels: 3) { t, level in
        let phase = [0, 2.1, 4.0, 1.1, 3.1], k = [1.0, 2, 1, 3, 2], f = [2.0, 3, 4][level]
        let span = [7.0, 10.5, 14.5][level]
        for i in 0..<5 {
            let v = 0.5 + 0.32 * sin(k[i] * f * t + phase[i]) + 0.18 * sin((k[i] + 1) * f * t + phase[i] * 1.7)
            let h = 2.6 + v * span
            NSBezierPath(roundedRect: NSRect(x: 1.6 + Double(i) * 3.9, y: 9 - h / 2, width: 2.8, height: h), xRadius: 1.4, yRadius: 1.4).fill()
        }
    }
}
