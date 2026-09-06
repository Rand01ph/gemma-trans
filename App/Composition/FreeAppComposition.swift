@MainActor
enum AppComposition {
    static func makeFeatures() -> any AppFeatures { EmptyAppFeatures() }
}
