import AppKit
import SwiftUI

enum GTGlassPalette {
    // Codex reference anchors. Large surfaces remain neutral; blue is reserved for
    // selection, the primary translation action, and the current-model state.
    static let codexLightAccent = Color(red: 2 / 255, green: 133 / 255, blue: 1)
    static let codexDarkAccent = Color(red: 51 / 255, green: 156 / 255, blue: 1)
    static let codexLightBackground = Color.white
    static let codexDarkBackground = Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)

    static let semanticBlue = Color(nsColor: NSColor(name: "GTCodexAccent") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 51 / 255, green: 156 / 255, blue: 1, alpha: 1)
            : NSColor(red: 2 / 255, green: 133 / 255, blue: 1, alpha: 1)
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
    static let semanticGreen = Color(red: 0.09, green: 0.66, blue: 0.36)
    static let semanticOrange = Color(red: 0.88, green: 0.48, blue: 0.18)
    static let semanticRed = Color(red: 0.84, green: 0.20, blue: 0.22)

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? codexDarkAccent : codexLightAccent
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

    static func primaryActionTint(for colorScheme: ColorScheme) -> Color {
        accent(for: colorScheme)
    }

}
