import SwiftUI
import AppKit

enum GlassMetrics {
    static let cardRadius: CGFloat = 18
    static let tileRadius: CGFloat = 14
    static let spacing: CGFloat = 14
}

extension View {
    func glassCard(radius: CGFloat = GlassMetrics.cardRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(Glass.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: radius))
    }
}

struct WindowGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
