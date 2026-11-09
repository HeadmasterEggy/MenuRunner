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
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct AmbientBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    private var strength: Double { scheme == .dark ? 0.35 : 0.28 }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                blob(.blue, size: w * 0.7, x: w * 0.15, y: h * 0.12)
                blob(.purple, size: w * 0.6, x: w * 0.9, y: h * 0.35)
                blob(.orange, size: w * 0.55, x: w * 0.2, y: h * 0.7)
                blob(.teal, size: w * 0.6, x: w * 0.85, y: h * 0.95)
            }
        }
        .blur(radius: 70)
        .allowsHitTesting(false)
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(color.opacity(strength)).frame(width: size, height: size).position(x: x, y: y)
    }
}

struct WindowBackdrop: View {
    var body: some View {
        ZStack {
            WindowGlassBackground()
            AmbientBackdrop()
        }
        .ignoresSafeArea()
    }
}
