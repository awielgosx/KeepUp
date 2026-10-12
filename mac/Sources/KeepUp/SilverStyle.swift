import SwiftUI

extension Color {
    /// Convenience initializer for the exact hex values from the PRIX
    /// glass styles spec.
    init(hex: String) {
        let hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// The "02 · Liquid Silver" background: an opaque brushed-metal diagonal
/// gradient plus a glossy top catch-light, per the PRIX glass styles spec.
struct SilverBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "#fcfdff"), location: 0),
                    .init(color: Color(hex: "#eceff4"), location: 0.30),
                    .init(color: Color(hex: "#dbe1e9"), location: 0.55),
                    .init(color: Color(hex: "#f4f6f9"), location: 0.76),
                    .init(color: Color(hex: "#d3dae2"), location: 1.0)
                ],
                startPoint: UnitPoint(x: 0.35, y: 0),
                endPoint: UnitPoint(x: 0.65, y: 1)
            )
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.white.opacity(0.7), Color.clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                Spacer()
            }
            .opacity(0.6)
            .allowsHitTesting(false)
        }
    }
}

/// The "02 · Liquid Silver" raised control chip — `.control` in the spec:
/// a light gradient, a bright top lip, a soft embossed shadow. Used for
/// the editor, sliders, and buttons.
struct SilverChip: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Color(hex: "#f7f9fb"), Color(hex: "#e7ecf1")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color(hex: "#283c5a").opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

/// The "02 · Liquid Silver" recessed track — `.seg` in the spec: a
/// darker, subtly inset groove that raised chips sit inside (the sidebar
/// background).
struct SilverRecessed: ViewModifier {
    var cornerRadius: CGFloat = 13

    func body(content: Content) -> some View {
        content
            .background(Color(red: 20 / 255, green: 35 / 255, blue: 55 / 255).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func silverChip(cornerRadius: CGFloat = 14) -> some View {
        modifier(SilverChip(cornerRadius: cornerRadius))
    }

    func silverRecessed(cornerRadius: CGFloat = 13) -> some View {
        modifier(SilverRecessed(cornerRadius: cornerRadius))
    }
}
