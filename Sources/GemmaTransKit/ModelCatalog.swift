import Foundation

public enum ModelFamily: String, Sendable, Codable { case gemma, hunyuanMT2 }

public struct ModelCatalogEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let repo: String
    public let family: ModelFamily
    public let estimatedBytes: UInt64
    public let defaultMaxTokens: Int
    public let defaultMaxInputChars: Int
}

public enum ModelCatalog {
    public static let autoID = "auto"

    public static let entries: [ModelCatalogEntry] = [
        ModelCatalogEntry(id: "gemma-e4b-4bit", displayName: "Gemma 4 E4B (4-bit)",
            repo: "mlx-community/gemma-4-e4b-it-4bit", family: .gemma,
            estimatedBytes: 4_900_000_000, defaultMaxTokens: 2048, defaultMaxInputChars: 1500),
        ModelCatalogEntry(id: "gemma-e2b-4bit", displayName: "Gemma 4 E2B (4-bit)",
            repo: "mlx-community/gemma-4-e2b-it-4bit", family: .gemma,
            estimatedBytes: 3_600_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 700),
        // Hy-MT2 两条目：Plan A 决策门通过后保留；不过则删除这两行（infra 不依赖它们）。
        ModelCatalogEntry(id: "hymt2-4bit", displayName: "Hy-MT2 1.8B (4-bit · 翻译专用)",
            repo: "mlx-community/Hy-MT2-1.8B-4bit", family: .hunyuanMT2,
            estimatedBytes: 1_100_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 1500),
        ModelCatalogEntry(id: "hymt2-8bit", displayName: "Hy-MT2 1.8B (8-bit · 翻译专用)",
            repo: "mlx-community/Hy-MT2-1.8B-8bit", family: .hunyuanMT2,
            estimatedBytes: 1_900_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 1500),
    ]

    public static func entry(id: String) -> ModelCatalogEntry? {
        entries.first { $0.id == id }
    }
}
