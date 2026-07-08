import SwiftUI

enum GTGlassPalette {
    static let warmNeutral = Color(red: 0.90, green: 0.86, blue: 0.80)
    static let coolNeutral = Color(red: 0.78, green: 0.80, blue: 0.82)
    static let innerNeutral = Color(red: 0.86, green: 0.84, blue: 0.80)
    static let lavender = Color(red: 0.72, green: 0.66, blue: 0.82)
    static let peach = Color(red: 0.96, green: 0.72, blue: 0.58)
    static let rose = Color(red: 0.86, green: 0.62, blue: 0.66)
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.055)

    static let semanticBlue = Color(red: 0.20, green: 0.42, blue: 0.72)
    static let semanticGreen = Color(red: 0.09, green: 0.66, blue: 0.36)
    static let semanticOrange = Color(red: 0.88, green: 0.48, blue: 0.18)
    static let semanticRed = Color(red: 0.84, green: 0.20, blue: 0.22)

    static func defaultSurfaceBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.34, green: 0.31, blue: 0.30)
            : warmNeutral
    }

    static func primaryActionFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white : ink
    }

    static func primaryActionForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? ink : Color.white
    }
}
