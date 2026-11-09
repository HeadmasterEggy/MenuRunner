import AppKit

final class MenuPanel: NSObject {
    private final class Window: NSPanel {
        var onEscape: () -> Void = {}
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { onEscape() }
    }

    private static let cornerRadius: CGFloat = 22
    private static let gap: CGFloat = 6
    private static let edge: CGFloat = 8
    private static let drop: CGFloat = 6

    private let window: Window
    private let content: NSView
    private var generation = 0
    var onClose: () -> Void = {}
    var onEscape: () -> Void = {} { didSet { window.onEscape = onEscape } }

    init(content: NSView, size: NSSize) {
        self.content = content
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
        let glass = GlassBackground.window(frame: bounds, cornerRadius: Self.cornerRadius, content: content)
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
        get { window.frame.size }
        set {
            guard newValue != window.frame.size else { return }
            let old = window.frame
            let target = clamp(NSRect(x: old.midX - newValue.width / 2, y: old.maxY - newValue.height,
                                      width: newValue.width, height: newValue.height), on: window.screen)
            window.setFrame(target, display: true, animate: window.isVisible)
            window.invalidateShadow()
        }
    }

    func show(below button: NSStatusBarButton) {
        guard let bw = button.window else { return }
        let anchor = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let size = window.frame.size
        let target = clamp(NSRect(x: anchor.midX - size.width / 2, y: anchor.minY - Self.gap - size.height,
                                  width: size.width, height: size.height), on: bw.screen)
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
