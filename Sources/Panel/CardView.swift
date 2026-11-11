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
    var cornerRadius: CGFloat = 18
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
        dragging = false
        if onClick != nil { pressed = true }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let onDrag, let start = downPoint, !dragging else { return }
        let p = pointInSuperview(event)
        guard hypot(p.x - start.x, p.y - start.y) > Self.dragThreshold else { return }
        dragging = true
        pressed = false
        hovered = false
        downPoint = nil
        onDrag(self, .began, start)
        onDrag(self, .moved, p)
        trackDrag(onDrag)
    }
    private func trackDrag(_ onDrag: @escaping (CardView, CardDragController.Phase, NSPoint) -> Void) {
        guard let window else { finishDrag(onDrag, at: downPoint ?? .zero); return }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { [weak self] event, stop in
            guard let self, let event else { stop.pointee = true; return }
            let p = self.pointInSuperview(event)
            if event.type == .leftMouseUp {
                self.finishDrag(onDrag, at: p)
                stop.pointee = true
            } else {
                onDrag(self, .moved, p)
            }
        }
        if dragging { finishDrag(onDrag, at: downPoint ?? .zero) }
    }
    private func finishDrag(_ onDrag: (CardView, CardDragController.Phase, NSPoint) -> Void, at point: NSPoint) {
        guard dragging else { return }
        dragging = false
        onDrag(self, .ended, point)
    }
    override func mouseUp(with event: NSEvent) {
        downPoint = nil
        guard !dragging else { return }
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
        CardView.drawingHeight = bounds.height
        drawer(bounds.width)
        CardView.drawingHover = nil
    }
}
