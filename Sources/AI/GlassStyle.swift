import SwiftUI

enum GlassMetrics {
    static let cardRadius: CGFloat = 18
    static let tileRadius: CGFloat = 14
    static let spacing: CGFloat = 14
}

extension View {
    @ViewBuilder func glassCard(radius: CGFloat = GlassMetrics.cardRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: radius))
        } else {
            background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint ?? .clear))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
        }
    }

    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = GlassMetrics.spacing
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
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
