import AppKit
import SwiftUI

/// "Follow system" by default: Cosmic Glass in dark mode, Liquid Silver
/// in light mode. Forcing one is done app-wide via NSApp.appearance, so
/// every window (including the desktop widget) and the colorScheme
/// environment agree.
enum ThemePref: String, CaseIterable, Identifiable {
    case auto, dark, light
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Follow system"
        case .dark: return "Cosmic Glass"
        case .light: return "Liquid Silver"
        }
    }

    static var current: ThemePref {
        ThemePref(rawValue: UserDefaults.standard.string(forKey: Pref.theme) ?? "") ?? .auto
    }

    static func apply() {
        switch current {
        case .auto: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
    }
}

/// Colors for the two looks, picked from the current color scheme.
struct Palette {
    let isDark: Bool

    var text: Color { isDark ? Color(red: 0.95, green: 0.96, blue: 1) : Color(hex: "#1b2533") }
    var dim: Color { isDark ? Color(red: 0.88, green: 0.9, blue: 1).opacity(0.68) : Color(hex: "#5d6b7e") }
    var faint: Color { isDark ? Color(red: 0.88, green: 0.9, blue: 1).opacity(0.42) : Color(hex: "#8a96a6") }
    var accent: Color { isDark ? Color(hex: "#8fa6ff") : Color(hex: "#3a5bd9") }
    var overdue: Color { isDark ? Color(hex: "#ff8a7a") : Color(hex: "#c2412d") }
    var today: Color { isDark ? Color(hex: "#a9b9ff") : Color(hex: "#3a5bd9") }
    var check: Color { isDark ? Color.white.opacity(0.4) : Color(hex: "#9aa6b6") }

    func tone(_ t: Due.Tone) -> Color {
        switch t {
        case .normal: return dim
        case .today: return today
        case .overdue: return overdue
        }
    }
}

/// Window / widget background: Cosmic Glass when dark, Liquid Silver when light.
struct ThemedPanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if scheme == .dark {
            content.cosmicGlass(cornerRadius: cornerRadius)
        } else {
            content
                .background(SilverBackground())
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                )
        }
    }
}

/// A row / control chip: faint glass tile when dark, raised silver chip when light.
struct ThemedChip: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 13

    @ViewBuilder
    func body(content: Content) -> some View {
        if scheme == .dark {
            content
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        } else {
            content.silverChip(cornerRadius: cornerRadius)
        }
    }
}

extension View {
    func themedPanel(cornerRadius: CGFloat = 26) -> some View {
        modifier(ThemedPanel(cornerRadius: cornerRadius))
    }

    func themedChip(cornerRadius: CGFloat = 13) -> some View {
        modifier(ThemedChip(cornerRadius: cornerRadius))
    }
}
