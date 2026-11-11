import AppKit
import QuartzCore

final class CardDragController {
    enum Phase { case began, moved, ended }

    private struct Slot {
        let card: CardView
        let glass: NSView?
        let kind: PanelCard
    }

    private static let shiftDuration = 0.32
    private static let dropDuration = 0.36
    private static let liftDuration = 0.18
    private static let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
    private static let liftAlpha: CGFloat = 0.94
    private static let shadowOpacity: Float = 0.3
    private static let shadowRadius: CGFloat = 16
    private static let shadowOffset = CGSize(width: 0, height: -8)

    private var slots: [Slot] = []
    private var order: [PanelCard] = []
    private var startOrder: [PanelCard] = []
    private var targets: [PanelCard: NSRect] = [:]
    private var dragged: Slot?
    private var grabOffset = NSPoint.zero
    private var lastSwapped: PanelCard?

    var frames: ([PanelCard]) -> [PanelCard: NSRect] = { _ in [:] }
    var onCommit: ([PanelCard]) -> Void = { _ in }
    var onAnimate: () -> Void = {}

    func attach(cards: [CardView], glass: [NSView], kinds: [PanelCard?]) {
        slots = cards.indices.compactMap { i in
            guard let kind = kinds[i] else { return nil }
            return Slot(card: cards[i], glass: i < glass.count ? glass[i] : nil, kind: kind)
        }
        order = slots.map(\.kind)
        for slot in slots {
            slot.card.onDrag = { [weak self] card, phase, point in self?.handle(card, phase, point) }
        }
    }

    private func handle(_ card: CardView, _ phase: Phase, _ point: NSPoint) {
        switch phase {
        case .began: begin(card, at: point)
        case .moved: move(card, to: point)
        case .ended: end(card)
        }
    }

    private func begin(_ card: CardView, at point: NSPoint) {
        guard dragged == nil, let slot = slots.first(where: { $0.card === card }) else { return }
        dragged = slot
        startOrder = order
        targets = frames(order)
        lastSwapped = nil
        grabOffset = NSPoint(x: point.x - card.frame.minX, y: point.y - card.frame.minY)
        card.superview?.addSubview(card)
        lift(card, true)
        NSCursor.closedHand.push()
    }

    private func move(_ card: CardView, to point: NSPoint) {
        guard let slot = dragged, slot.card === card else { return }
        card.setFrameOrigin(NSPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y))
        if let last = lastSwapped, !(targets[last]?.contains(point) ?? false) { lastSwapped = nil }
        guard let hit = order.first(where: { $0 != slot.kind && $0 != lastSwapped && (targets[$0]?.contains(point) ?? false) }),
              let from = order.firstIndex(of: slot.kind), let to = order.firstIndex(of: hit) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        lastSwapped = hit
        targets = frames(order)
        animate(Self.shiftDuration) {
            for other in self.slots {
                guard let frame = self.targets[other.kind] else { continue }
                other.glass?.animator().frame = frame
                if other.kind != slot.kind { other.card.animator().frame = frame }
            }
        }
    }

    private func end(_ card: CardView) {
        guard let slot = dragged, slot.card === card else { return }
        NSCursor.pop()
        dragged = nil
        let finalOrder = order
        let changed = finalOrder != startOrder
        animate(Self.dropDuration, {
            if let frame = self.targets[slot.kind] {
                card.animator().frame = frame
                slot.glass?.animator().frame = frame
            }
            self.lift(card, false)
        }, completion: { [weak self] in
            guard let self, changed else { return }
            self.onCommit(finalOrder)
        })
    }

    private func animate(_ duration: Double, _ changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        onAnimate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = Self.timing
            ctx.allowsImplicitAnimation = true
            changes()
        }, completionHandler: completion)
    }

    private func lift(_ card: CardView, _ lifted: Bool) {
        card.wantsLayer = true
        guard let layer = card.layer else { return }
        if lifted {
            card.effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
            }
            layer.cornerRadius = card.cornerRadius
            layer.cornerCurve = .continuous
            layer.masksToBounds = false
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowRadius = Self.shadowRadius
            layer.shadowOffset = Self.shadowOffset
        }
        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
        shadow.toValue = lifted ? Self.shadowOpacity : 0
        shadow.duration = lifted ? Self.liftDuration : Self.dropDuration
        shadow.timingFunction = Self.timing
        layer.add(shadow, forKey: "lift")
        layer.shadowOpacity = lifted ? Self.shadowOpacity : 0
        let background = CABasicAnimation(keyPath: "backgroundColor")
        background.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        background.duration = shadow.duration
        background.timingFunction = Self.timing
        if !lifted {
            background.toValue = NSColor.clear.cgColor
            layer.add(background, forKey: "liftBackground")
            layer.backgroundColor = nil
        }
        card.animator().alphaValue = lifted ? Self.liftAlpha : 1
    }
}
