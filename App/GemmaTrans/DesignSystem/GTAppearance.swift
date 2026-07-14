import AppKit
import Observation
import SwiftUI
import GemmaTransKit

extension AppAppearance {
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
@Observable
final class GTAppearanceStore {
    static let shared = GTAppearanceStore()

    var appearance: AppAppearance

    private init() {
        appearance = AppSettings.load().appearance
        apply(appearance)
    }

    func set(_ newValue: AppAppearance, persist: Bool) {
        appearance = newValue
        apply(newValue)
        guard persist else { return }
        var settings = AppSettings.load()
        settings.appearance = newValue
        settings.save()
    }

    func reloadFromDefaults() {
        set(AppSettings.load().appearance, persist: false)
    }

    private func apply(_ value: AppAppearance) {
        NSApplication.shared.appearance = value.nsAppearance
        // AppKit is the single appearance source for every SwiftUI host and NSPanel.
        // Clearing per-window overrides is essential when moving from a forced mode
        // back to `system`; `.preferredColorScheme(nil)` can retain the previous mode.
        for window in NSApplication.shared.windows {
            window.appearance = nil
            window.contentView?.appearance = nil
            window.contentView?.needsDisplay = true
        }
    }
}

struct GTApplicationAppearance: ViewModifier {
    @State private var appearanceStore = GTAppearanceStore.shared

    func body(content: Content) -> some View {
        content
            .onAppear { appearanceStore.reloadFromDefaults() }
    }
}

extension View {
    func gtApplicationAppearance() -> some View {
        modifier(GTApplicationAppearance())
    }
}
