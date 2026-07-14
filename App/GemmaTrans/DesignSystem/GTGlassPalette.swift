import SwiftUI

enum GTGlassPalette {
    // Quiet Glass: large surfaces stay neutral. Color is reserved for status and actions.
    static let warmNeutral = Color(red: 0.64, green: 0.63, blue: 0.61)
    static let coolNeutral = Color(red: 0.48, green: 0.50, blue: 0.53)
    static let innerNeutral = Color(red: 0.56, green: 0.57, blue: 0.59)
    static let lavender = Color(red: 0.49, green: 0.47, blue: 0.56)
    static let peach = Color(red: 0.66, green: 0.55, blue: 0.49)
    static let rose = Color(red: 0.64, green: 0.46, blue: 0.49)
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.055)

    static let semanticBlue = Color(red: 0.20, green: 0.42, blue: 0.72)
    static let semanticGreen = Color(red: 0.09, green: 0.66, blue: 0.36)
    static let semanticOrange = Color(red: 0.88, green: 0.48, blue: 0.18)
    static let semanticRed = Color(red: 0.84, green: 0.20, blue: 0.22)

    static func defaultSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.17, blue: 0.18)
            : Color(red: 0.82, green: 0.84, blue: 0.87)
    }

    static func contentSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.095, green: 0.10, blue: 0.11)
            : Color(red: 0.94, green: 0.955, blue: 0.975)
    }

    static func formSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.19, blue: 0.20)
            : Color(red: 0.90, green: 0.92, blue: 0.945)
    }

    static func subtleSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.25, green: 0.26, blue: 0.28)
            : Color(red: 0.72, green: 0.75, blue: 0.80)
    }

    static func backgroundOverlay(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.24)
            : Color.black.opacity(0.025)
    }

    static func neutralControlTint(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.34, green: 0.36, blue: 0.40).opacity(0.68)
            : Color(red: 0.78, green: 0.80, blue: 0.84).opacity(0.58)
    }

    static func primaryActionTint(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.30, green: 0.52, blue: 0.90)
            : Color(red: 0.11, green: 0.35, blue: 0.78)
    }

    static func positiveForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? semanticGreen
            : Color(red: 0.04, green: 0.46, blue: 0.20)
    }

    static func positiveSurfaceTint(for colorScheme: ColorScheme) -> Color {
        positiveForeground(for: colorScheme)
            .opacity(colorScheme == .dark ? 0.16 : 0.11)
    }

    static func primaryActionFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white : ink
    }

    static func primaryActionForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? ink : Color.white
    }
}
