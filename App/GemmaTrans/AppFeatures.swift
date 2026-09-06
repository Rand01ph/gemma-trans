import SwiftUI
import GemmaTransKit

/// Distribution-specific functionality is supplied at build time. The shared app owns the engine
/// and windows; an extension only supplies a prompt provider and optional UI surfaces.
@MainActor
protocol AppFeatures {
    var promptProvider: (any TranslationPromptProvider)? { get }
    var settingsTitle: String? { get }
    func settingsView() -> AnyView
    func scenePicker() -> AnyView
    func menuContent() -> AnyView
}

@MainActor
enum AppFeatureRegistry {
    static let current: any AppFeatures = AppComposition.makeFeatures()
}

struct EmptyAppFeatures: AppFeatures {
    var promptProvider: (any TranslationPromptProvider)? { nil }
    var settingsTitle: String? { nil }
    func settingsView() -> AnyView { AnyView(EmptyView()) }
    func scenePicker() -> AnyView { AnyView(EmptyView()) }
    func menuContent() -> AnyView { AnyView(EmptyView()) }
}
