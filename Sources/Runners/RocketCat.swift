import AppKit

extension Runner {
    static let rocketCat = Runner(id: "rocket", name: "橘猫火箭|Rocket Cat", frameCount: 12, size: NSSize(width: 36, height: 20), template: false, levels: 3) { t, level in
        let W = 36, H = 20
        let f12 = Int((t / (2 * .pi) * 12).rounded()) % 12
        let f = f12 % 6
        let g = Int(Double(f12) * [1, 1.5, 2][level]) % 6
        func c(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        let orange = c(0.97, 0.60, 0.20), stripe = c(0.82, 0.40, 0.10), white = c(0.99, 0.97, 0.93)
        let pink = c(0.99, 0.56, 0.66), eye = c(0.10, 0.09, 0.12), outline = c(0.16, 0.13, 0.18)
        let hull = c(0.90, 0.92, 0.96), hullShade = c(0.66, 0.70, 0.79), red = c(0.92, 0.22, 0.24)
        let glass = c(0.40, 0.74, 0.99), glassDark = c(0.16, 0.38, 0.74), nozzle = c(0.38, 0.38, 0.44)
        let flameY = c(1.0, 0.90, 0.30), flameO = c(1.0, 0.56, 0.16), flameR = c(0.96, 0.27, 0.22)

        var grid = [[NSColor?]](repeating: [NSColor?](repeating: nil, count: W), count: H)
        let bob = f % 2 + 1
        func set(_ x: Int, _ y: Int, _ col: NSColor) {
            let yy = y + bob
            if x >= 0 && x < W && yy >= 0 && yy < H { grid[yy][x] = col }
        }
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ col: NSColor) {
            for y in y0...y1 { for x in x0...x1 { set(x, y, col) } }
        }

        rect(12, 10, 29, 14, hull)
        rect(12, 14, 29, 14, hullShade)
        for (y, len) in [(10, 2), (11, 3), (12, 4), (13, 3), (14, 2)] { rect(30, y, 29 + len, y, red) }
        rect(12, 7, 14, 9, red); set(15, 9, red)
        rect(12, 15, 14, 16, red); set(15, 15, red)
        rect(10, 11, 11, 13, nozzle)
        rect(24, 11, 26, 13, glassDark); set(25, 12, glass); set(24, 11, glass)

        rect(16, 4, 22, 9, orange)
        for x in [17, 19] { rect(x, 4, x, 6, stripe) }
        rect(20, 6, 22, 9, white)
        rect(21, 1, 27, 6, orange)
        set(21, 0, orange); set(22, 0, orange); set(26, 0, orange); set(27, 0, orange)
        set(22, 1, pink); set(26, 1, pink)
        set(24, 1, stripe); set(24, 2, stripe)
        set(23, 3, eye); set(26, 3, eye)
        rect(23, 4, 26, 5, white)
        set(24, 4, pink)
        set(22, 4, pink); set(27, 4, pink)
        rect(22, 9, 24, 9, white)
        let tailY = [5, 4, 4, 5, 6, 6][f]
        set(15, 7, orange); set(14, tailY + 1, orange); set(13, tailY, orange); set(12, tailY, stripe)

        let solid = grid.map { $0.map { $0 != nil } }
        for y in 0..<H { for x in 0..<W where !solid[y][x] {
            let n = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            if n.contains(where: { $0.0 >= 0 && $0.0 < W && $0.1 >= 0 && $0.1 < H && solid[$0.1][$0.0] }) { grid[y][x] = outline }
        } }

        let len = [[4, 5, 5, 6, 5, 4], [6, 8, 7, 9, 6, 8], [10, 7, 10, 8, 10, 7]][level][g]
        let rows = level == 2 ? [(10, 4), (11, 1), (12, 0), (13, 1), (14, 4)] : [(11, 2), (12, 0), (13, 2)]
        for (dy, short) in rows {
            let l = len - short
            for i in 0..<max(l, 0) {
                let x = 9 - i
                let col = i < l / 3 ? flameY : (i < l * 2 / 3 ? flameO : flameR)
                if x >= 0 && grid[dy + bob][x] == nil { grid[dy + bob][x] = col }
            }
        }

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setShouldAntialias(false)
        for y in 0..<H { for x in 0..<W { if let col = grid[y][x] { col.setFill(); NSRect(x: x, y: H - 1 - y, width: 1, height: 1).fill() } } }

        for (sx, sy, ph) in [(3, 3, 0), (32, 2, 2), (6, 18, 4), (34, 17, 1)] {
            let phase = (g + ph) % 6
            guard phase < 4 else { continue }
            let col = NSColor(srgbRed: 1, green: 0.78, blue: 0.18, alpha: phase == 1 ? 1 : 0.75)
            col.setFill()
            NSRect(x: sx, y: H - 1 - sy, width: 1, height: 1).fill()
            if phase == 1 {
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { NSRect(x: sx + dx, y: H - 1 - sy - dy, width: 1, height: 1).fill() }
            }
        }
    }

}
