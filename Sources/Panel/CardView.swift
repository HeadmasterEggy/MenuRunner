import AppKit

final class CardView: NSView {
    var continuous = false
    var rowAt: ((NSPoint) -> String?)?
    private(set) var hoverPoint: NSPoint?
    static var drawingHover: NSPoint?
    static var drawingHeight: CGFloat = 0
    var drawer: (CGFloat) -> Void = { _ in }
    var onClick: (() -> Void)?
    var onDrag: ((CardView, CardDragController.Phase, NSPoint) -> Void)?
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }
    private static let dragThreshold: CGFloat = 4
    private var downPoint: NSPoint?
    private var dragging = false
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }
    private func pointInSuperview(_ event: NSEvent) -> NSPoint {
        superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
    }
    override func mouseDown(with event: NSEvent) {
        downPoint = pointInSuperview(event)
        if onClick != nil { pressed = true }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let onDrag, let start = downPoint else { return }
        let p = pointInSuperview(event)
        if !dragging, hypot(p.x - start.x, p.y - start.y) > Self.dragThreshold {
            dragging = true
            pressed = false
            hovered = false
            onDrag(self, .began, start)
        }
        if dragging { onDrag(self, .moved, p) }
    }
    override func mouseUp(with event: NSEvent) {
        downPoint = nil
        if dragging {
            dragging = false
            onDrag?(self, .ended, pointInSuperview(event))
            return
        }
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
        if isDropTarget {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 17, yRadius: 17)
            ring.lineWidth = 3
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            ring.fill()
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
        CardView.drawingHover = rowAt != nil ? hoverPoint : nil
        CardView.drawingHeight = bounds.height
        drawer(bounds.width)
        CardView.drawingHover = nil
    }
}
