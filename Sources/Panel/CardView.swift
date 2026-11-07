import AppKit

final class CardView: NSView {
    var continuous = false
    var rowAt: ((NSPoint) -> String?)?
    private(set) var hoverPoint: NSPoint?
    static var drawingHover: NSPoint?
    var drawer: (CGFloat) -> Void = { _ in }
    var onClick: (() -> Void)?
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }
    override func mouseDown(with event: NSEvent) { if onClick != nil { pressed = true } }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(p)
        pressed = false
        if inside, let path = rowAt?(p) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return
        }
        if inside { onClick?() }
    }
    override func mouseMoved(with event: NSEvent) {
        guard rowAt != nil else { return }
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        if let p = hoverPoint, rowAt?(p) != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
    override func mouseEntered(with event: NSEvent) { hovered = onClick != nil }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false; hoverPoint = nil; if rowAt != nil { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func resetCursorRects() { if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }
    static var drawCount = 0
    override func draw(_ dirtyRect: NSRect) {
        CardView.drawCount += 1
        if hovered || pressed {
            NSColor.labelColor.withAlphaComponent(pressed ? 0.12 : 0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        }
        CardView.drawingHover = rowAt != nil ? hoverPoint : nil
        drawer(bounds.width)
        CardView.drawingHover = nil
    }
}
