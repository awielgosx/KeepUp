import SwiftUI
import AppKit

/// AppKit blur backing for the "Cosmic Glass" look (style 01 from the
/// PRIX glass styles spec).
struct CosmicGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Applies the Cosmic Glass chrome, following the spec's layer recipe:
/// a near-transparent white fill, blur, a top inset highlight line, a
/// blue under-glow pooling at the bottom, a border, a diagonal specular
/// streak, and a soft drop shadow.
///
/// One deliberate deviation: the spec assumes a fixed, designed-in dark
/// nebula background behind the glass (it says so explicitly — "no
/// background = invisible effect"). This panel instead floats over
/// whatever's on your actual desktop, which the spec's CSS was never
/// built to handle, so an extra dark base tint is layered in first —
/// without it the glass reads as washed-out/light over a bright desktop.
/// Every other layer follows the spec's values.
struct CosmicGlassChrome: ViewModifier {
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    CosmicGlassBackground()
                    Color.black.opacity(0.55)
                    Color.white.opacity(0.07)
                }
            )
            .overlay(underGlow)
            .overlay(topHighlightLine)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .overlay(specularStreak)
        // No drop shadow: an NSWindow can never draw outside its own
        // rectangular frame, so ANY shadow blur radius gets hard-clipped
        // at the window edge before it's had room to fade to nothing —
        // that hard cutoff is exactly the visible "square behind the
        // rounded corners" that kept showing up. Shrinking the radius
        // made it smaller but never eliminated it, since some clipping
        // happens at any non-zero radius; removing it is what actually
        // guarantees fully transparent corners.
    }

    /// `inset 0 1px 0 rgba(255,255,255,.5)` — the lit top edge.
    private var topHighlightLine: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// `inset 0 -14px 30px -20px rgba(120,150,255,.25)` — a faint blue
    /// bloom pooling at the bottom, reading as refracted light.
    private var underGlow: some View {
        VStack(spacing: 0) {
            Spacer()
            Ellipse()
                .fill(Color(red: 0.47, green: 0.59, blue: 1.0).opacity(0.25))
                .frame(height: 50)
                .blur(radius: 22)
                .offset(y: 24)
        }
        .allowsHitTesting(false)
    }

    /// `linear-gradient(135deg, rgba(255,255,255,.35), transparent 40%)` —
    /// the diagonal catch-light sweeping across the top-left.
    private var specularStreak: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), Color.clear],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.4, y: 0.4)
                )
            )
            .opacity(0.5)
            .allowsHitTesting(false)
    }
}

extension View {
    func cosmicGlass(cornerRadius: CGFloat = 26) -> some View {
        modifier(CosmicGlassChrome(cornerRadius: cornerRadius))
    }
}
