import AppKit

final class CardDragController {
    enum Phase { case began, moved, ended }

    private static let cornerRadius: CGFloat = 18
    private static let settleDuration = 0.22

    private var cards: [CardView] = []
    private var kinds: [PanelCard?] = []
    private var dragged: CardView?
    private var origin = NSPoint.zero
    private var start = NSPoint.zero
    private var target: CardView? {
        didSet {
            guard target !== oldValue else { return }
            oldValue?.isDropTarget = false
            target?.isDropTarget = true
        }
    }
    var onMove: (PanelCard, PanelCard) -> Void = { _, _ in }

    func attach(cards: [CardView], kinds: [PanelCard?]) {
        self.cards = cards
        self.kinds = kinds
        for (card, kind) in zip(cards, kinds) where kind != nil {
            card.onDrag = { [weak self] card, phase, point in self?.handle(card, phase, point) }
        }
    }

    private func kind(of card: CardView) -> PanelCard? {
        cards.firstIndex(where: { $0 === card }).flatMap { kinds[$0] }
    }

    private func handle(_ card: CardView, _ phase: Phase, _ point: NSPoint) {
        switch phase {
        case .began: begin(card, at: point)
        case .moved: move(card, to: point)
        case .ended: end(card)
        }
    }

    private func begin(_ card: CardView, at point: NSPoint) {
        dragged = card
        origin = card.frame.origin
        start = point
        card.superview?.addSubview(card)
        lift(card, true)
        NSCursor.closedHand.push()
    }

    private func move(_ card: CardView, to point: NSPoint) {
        guard dragged === card else { return }
        card.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
        target = cards.first { other in
            other !== card && kind(of: other) != nil && other.frame.contains(point)
        }
    }

    private func end(_ card: CardView) {
        guard dragged === card else { return }
        NSCursor.pop()
        let from = kind(of: card), to = target.flatMap(kind(of:))
        target = nil
        dragged = nil
        if let from, let to {
            lift(card, false)
            DispatchQueue.main.async { [weak self] in self?.onMove(from, to) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.settleDuration
            ctx.allowsImplicitAnimation = true
            card.animator().setFrameOrigin(origin)
        }, completionHandler: { [weak self] in self?.lift(card, false) })
    }

    private func lift(_ card: CardView, _ lifted: Bool) {
        card.wantsLayer = true
        guard let layer = card.layer else { return }
        if lifted {
            card.effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
            }
            layer.cornerRadius = Self.cornerRadius
            layer.cornerCurve = .continuous
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.28
            layer.shadowRadius = 14
            layer.shadowOffset = CGSize(width: 0, height: -6)
            layer.masksToBounds = false
            card.alphaValue = 0.96
        } else {
            layer.backgroundColor = nil
            layer.shadowOpacity = 0
            card.alphaValue = 1
        }
    }
}
