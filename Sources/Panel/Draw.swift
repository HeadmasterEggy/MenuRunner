import AppKit

extension NSColor {
    static var glassSecondary: NSColor { NSColor.labelColor.withAlphaComponent(0.72) }
    static var glassTertiary: NSColor { NSColor.labelColor.withAlphaComponent(0.5) }
}

enum Draw {
    static func text(_ s: String, _ p: NSPoint, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                     color: NSColor = .labelColor, right: Bool = false, mono: Bool = false, maxWidth: CGFloat? = nil) {
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        if let mw = maxWidth, str.size().width > mw {
            let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps])
                .draw(with: NSRect(x: p.x, y: p.y, width: mw, height: str.size().height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return
        }
        str.draw(at: NSPoint(x: right ? p.x - str.size().width : p.x, y: p.y))
    }

    @discardableResult
    static func symbol(_ name: String, _ p: NSPoint, size: CGFloat = 12, color: NSColor = .secondaryLabelColor) -> CGFloat {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return 0 }
        let tinted = NSImage(size: img.size, flipped: false) { r in img.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
        tinted.draw(in: NSRect(x: p.x, y: p.y + (16 - img.size.height) / 2, width: img.size.width, height: img.size.height))
        return img.size.width
    }

    @discardableResult
    static func title(_ icon: String, _ name: String, in w: CGFloat, tint: NSColor = .labelColor, chevron: Bool = true) -> CGFloat {
        let iw = symbol(icon, NSPoint(x: 14, y: 12), size: 13, color: tint)
        let x = 14 + max(iw, 14) + 6
        text(name, NSPoint(x: x, y: 12), size: 12, weight: .semibold)
        let tw = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
        guard chevron else { return x + tw }
        let cw = symbol("chevron.right", NSPoint(x: x + tw + 4, y: 12), size: 9, color: .glassTertiary)
        return x + tw + 4 + cw
    }

    static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func level(_ f: Double) -> NSColor { f < 0.7 ? .systemGreen : (f < 0.9 ? .systemYellow : .systemRed) }
    static func tempColor(_ c: Double) -> NSColor { c < 60 ? .systemGreen : (c < 80 ? .systemYellow : .systemRed) }

    static func bar(_ r: NSRect, _ f: Double, _ color: NSColor) {
        let rad = r.height / 2
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad).fill()
        guard f > 0.005 else { return }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: max(r.height, r.width * CGFloat(min(f, 1))), height: r.height),
                     xRadius: rad, yRadius: rad).fill()
    }

    static func area(_ r: NSRect, _ values: [Double], scroll: Double, color: NSColor, line: Bool = false, dot: Bool = false) {
        guard values.count >= 2 else { return }
        let step = r.width / CGFloat(StatsModel.historyLength - 2)
        let shift = step * CGFloat(1 - scroll)
        func pt(_ i: Int) -> NSPoint {
            NSPoint(x: r.maxX - step * CGFloat(values.count - 1 - i) + shift,
                    y: r.maxY - r.height * CGFloat(min(max(values[i], 0), 1)))
        }
        let path = NSBezierPath()
        path.move(to: pt(0))
        for i in 1..<values.count {
            let p0 = pt(i - 1), p1 = pt(i)
            let mid = NSPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            path.curve(to: mid, controlPoint1: NSPoint(x: (p0.x + mid.x) / 2, y: p0.y), controlPoint2: NSPoint(x: (p0.x + mid.x) / 2, y: mid.y))
            if i == values.count - 1 { path.line(to: p1) }
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).addClip()
        if line {
            path.lineWidth = 1.6; path.lineJoinStyle = .round; color.setStroke(); path.stroke()
        } else {
            let fill = path.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: pt(values.count - 1).x, y: r.maxY + 1))
            fill.line(to: NSPoint(x: pt(0).x, y: r.maxY + 1)); fill.close()
            NSGradient(starting: color.withAlphaComponent(0.55), ending: color.withAlphaComponent(0.08))!.draw(in: fill, angle: 90)
            path.lineWidth = 1.6; color.setStroke(); path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        if dot {
            let a = pt(values.count - 2), b = pt(values.count - 1)
            let y = a.y + (b.y - a.y) * CGFloat(scroll)
            let c = NSPoint(x: r.maxX - 1, y: min(max(y, r.minY + 3), r.maxY - 3))
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)).fill()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 2.6, y: c.y - 2.6, width: 5.2, height: 5.2)).fill()
        }
    }

    static func chartBackground(_ r: NSRect, grid: Bool = true) {
        NSColor.labelColor.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        guard grid else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setStroke()
        for f in [0.25, 0.5, 0.75] {
            let y = r.maxY - r.height * CGFloat(f)
            let line = NSBezierPath()
            line.lineWidth = 0.5
            line.setLineDash([2, 3], count: 2, phase: 0)
            line.move(to: NSPoint(x: r.minX + 6, y: y)); line.line(to: NSPoint(x: r.maxX - 6, y: y))
            line.stroke()
        }
    }
}
