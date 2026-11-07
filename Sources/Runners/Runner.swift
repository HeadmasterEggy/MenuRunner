import AppKit

func strokeLine(_ pts: [NSPoint], _ w: CGFloat) {
    let p = NSBezierPath()
    p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }
    p.stroke()
}

func punch(_ draw: () -> Void) {
    NSGraphicsContext.current?.compositingOperation = .clear
    draw()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
}

struct Runner {
    let id: String
    let name: String
    let frameCount: Int
    let size: NSSize
    var template = true
    var levels = 1
    let draw: (_ t: Double, _ level: Int) -> Void

    var displayName: String { let p = name.split(separator: "|").map(String.init); return L(p[0], p.count > 1 ? p[1] : p[0]) }

    func frames(appearance: NSAppearance? = nil, level: Int = 0) -> [NSImage] {
        (0..<frameCount).map { i in
            let scale: CGFloat = 2
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let render = {
                NSColor.black.setFill(); NSColor.black.setStroke()
                self.draw(Double(i) / Double(self.frameCount) * 2 * .pi, level)
            }
            if let appearance { appearance.performAsCurrentDrawingAppearance(render) } else { render() }
            NSGraphicsContext.restoreGraphicsState()
            let img = NSImage(size: size)
            img.addRepresentation(rep)
            img.isTemplate = template
            return img
        }
    }

    static let all: [Runner] = [coffee, rocketCat, fan, pulse, bars, hourglass, lavaLamp, dna, radar, ball, clock]

}

func pt(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x, y: y) }
