import AppKit

final class MenuPanel: NSObject {
    private final class Window: NSPanel {
        var onEscape: () -> Void = {}
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { onEscape() }
    }

    private final class TopAnchoredView: NSView {
        override var isFlipped: Bool { true }
    }

    private static let cornerRadius: CGFloat = 22
    private static let gap: CGFloat = 6
    private static let edge: CGFloat = 8
    private static let drop: CGFloat = 6
    private static let resizeDuration: TimeInterval = 0.2
    private static let minimumHeight: CGFloat = 160

    private let window: Window
    private let content: NSView
    private let document: TopAnchoredView
    private let scroll: NSScrollView
    private var pageSize: NSSize
    private var anchorTop: CGFloat?
    private var generation = 0
    var onClose: () -> Void = {}
    var onEscape: () -> Void = {} { didSet { window.onEscape = onEscape } }

    init(content: NSView, size: NSSize) {
        self.content = content
        pageSize = size
        document = TopAnchoredView(frame: NSRect(origin: .zero, size: size))
        scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        window = Window(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.isFloatingPanel = true
        window.level = .popUpMenu
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        content.frame = NSRect(origin: .zero, size: size)
        let bounds = NSRect(origin: .zero, size: size)
        let clip = NSView(frame: bounds)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Self.cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.layer?.backgroundColor = NSColor.clear.cgColor
        document.addSubview(content)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.contentView.drawsBackground = false
        scroll.documentView = document
        scroll.autoresizingMask = [.width, .height]
        let glass = GlassBackground.window(frame: bounds, cornerRadius: Self.cornerRadius, content: scroll)
        glass.autoresizingMask = [.width, .height]
        clip.addSubview(glass)
        window.contentView = clip
    }

    var isShown: Bool { window.isVisible }
    var frame: NSRect { window.frame }
    var screen: NSScreen? { window.screen }

    var appearance: NSAppearance? {
        get { window.appearance }
        set { window.appearance = newValue }
    }

    var contentSize: NSSize {
        get { pageSize }
        set {
            pageSize = newValue
            document.setFrameSize(newValue)
            content.frame = NSRect(origin: .zero, size: newValue)
            scrollToTop()
            let target = fittedFrame(top: anchorTop ?? window.frame.maxY, screen: window.screen)
            updateScrolling(visibleHeight: target.height)
            guard target != window.frame else { return }
            guard window.isVisible else { window.setFrame(target, display: false); return }
            NSAnimationContext.runAnimationGroup({ c in
                c.duration = Self.resizeDuration
                c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in self?.window.invalidateShadow() })
        }
    }

    func show(below button: NSStatusBarButton) {
        guard let bw = button.window else { return }
        let anchor = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let top = anchor.minY - Self.gap
        anchorTop = top
        var target = fittedFrame(top: top, screen: bw.screen)
        target.origin.x = anchor.midX - target.width / 2
        target = clamp(target, on: bw.screen)
        updateScrolling(visibleHeight: target.height)
        scrollToTop()
        generation += 1
        window.setFrame(target.offsetBy(dx: 0, dy: Self.drop), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.18
            c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in self?.window.invalidateShadow() })
    }

    private func fittedFrame(top: CGFloat, screen: NSScreen?) -> NSRect {
        let old = window.frame
        var height = pageSize.height
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            height = min(height, max(top - visible.minY - Self.edge, Self.minimumHeight))
        }
        let frame = NSRect(x: old.midX - pageSize.width / 2, y: top - height, width: pageSize.width, height: height)
        return clamp(frame, on: screen)
    }

    private func updateScrolling(visibleHeight: CGFloat) {
        let overflows = pageSize.height > visibleHeight + 0.5
        scroll.verticalScrollElasticity = overflows ? .automatic : .none
        scroll.hasVerticalScroller = overflows
        if !overflows { scrollToTop() }
    }

    private func scrollToTop() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func close() {
        guard window.isVisible else { return }
        generation += 1
        let w = window, closing = generation
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.14
            c.timingFunction = CAMediaTimingFunction(name: .easeIn)
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == closing else { return }
            w.orderOut(nil)
            w.alphaValue = 1
            self.onClose()
        })
    }

    private func clamp(_ r: NSRect, on screen: NSScreen?) -> NSRect {
        guard let s = (screen ?? NSScreen.main)?.frame else { return r }
        var f = r
        f.origin.x = min(max(f.minX, s.minX + Self.edge), s.maxX - Self.edge - f.width)
        return f
    }
}
