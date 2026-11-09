import AppKit

enum GlassBackground {
    static func card(frame: NSRect, cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            return glass
        }
        return FallbackCardView(frame: frame, cornerRadius: cornerRadius)
    }

    static func group(frame: NSRect, spacing: CGFloat, content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView(frame: frame)
            container.spacing = spacing
            container.contentView = content
            return container
        }
        content.frame = frame
        return content
    }

    static func window(frame: NSRect, cornerRadius: CGFloat, content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.autoresizingMask = [.width, .height]
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView(frame: frame)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.autoresizingMask = [.width, .height]
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        return material
    }
}

final class FallbackCardView: NSView {
    private static let lightFill = 0.07
    private static let darkFill = 0.09
    private static let borderAlpha = 0.08

    init(frame: NSRect, cornerRadius: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base: NSColor = dark ? .white : .black
        layer?.backgroundColor = base.withAlphaComponent(dark ? Self.darkFill : Self.lightFill).cgColor
        layer?.borderColor = base.withAlphaComponent(Self.borderAlpha).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
