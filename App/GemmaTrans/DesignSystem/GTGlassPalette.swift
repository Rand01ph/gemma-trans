import AppKit
import SwiftUI

enum GTGlassPalette {
    // Codex reference anchors. Large surfaces and routine actions remain neutral;
    // Accent is reserved for focus and small selection markers.
    static let codexLightBackground = Color.white
    static let codexDarkBackground = Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)

    static var controlAccent: Color {
        let resolved = NSColor.controlAccentColor.usingColorSpace(.sRGB)
            ?? NSColor.controlAccentColor
        return Color(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            opacity: Double(resolved.alphaComponent)
        )
    }

    static let accentForeground = Color(nsColor: NSColor(name: "GTAccentForeground") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
            ?? NSColor.controlAccentColor
        guard isDark else { return accent }
        // A small white blend keeps the user's Accent hue while reducing the
        // high-chroma blue-on-black vibration in dark mode.
        return accent.blended(withFraction: 0.25, of: .white) ?? accent
    })

    static let secondaryTextNSColor = NSColor(name: "GTSecondaryText") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(white: 1, alpha: 0.68) : NSColor(white: 0, alpha: 0.58)
    }
    static let secondaryText = Color(nsColor: secondaryTextNSColor)
    static let tertiaryText = Color(nsColor: NSColor(name: "GTTertiaryText") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(white: 1, alpha: 0.58) : NSColor(white: 0, alpha: 0.54)
    })
    static let semanticReady = Color(nsColor: .systemGreen)
    static let semanticRed = Color(nsColor: .systemRed)

    static func accent(for _: ColorScheme) -> Color {
        accentForeground
    }

    static func primaryControlTint(for _: ColorScheme) -> Color {
        controlAccent
    }

    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? codexDarkBackground : codexLightBackground
    }

    static func defaultSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.12)
            : Color.white
    }

    static func contentSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.97, green: 0.97, blue: 0.97)
    }

    static func formSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.15)
            : Color(red: 0.95, green: 0.95, blue: 0.95)
    }

    static func subtleSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.18)
            : Color(red: 0.92, green: 0.92, blue: 0.92)
    }

    static func separator(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.13)
    }

    static func controlBoundary(for colorScheme: ColorScheme, increased: Bool = false) -> Color {
        if colorScheme == .dark {
            return increased
                ? Color(red: 0.62, green: 0.62, blue: 0.62)
                : Color(red: 0.47, green: 0.47, blue: 0.47)
        }
        return increased
            ? Color(red: 0.38, green: 0.38, blue: 0.38)
            : Color(red: 0.52, green: 0.52, blue: 0.52)
    }
}
