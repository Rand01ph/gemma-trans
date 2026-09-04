import Foundation

public enum ModelFamily: String, Sendable, Codable { case gemma, hunyuanMT2 }

enum GGUFQuantization: Sendable, Equatable {
    case stq1_0
    case q2_0c
}

enum ModelBackend: Sendable, Equatable {
    case mlx
    case llamaGGUF(GGUFQuantization)
}

struct SingleFileDistribution: Sendable, Equatable {
    let fileName: String
    let huggingFaceRevision: String
    let modelScopeRevision: String
    let bytes: Int64
    let sha256: String
}

enum ModelDistribution: Sendable, Equatable {
    case repositorySnapshot
    case singleFile(SingleFileDistribution)
}

public struct ModelCatalogEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let repo: String
    public let family: ModelFamily
    public let estimatedBytes: UInt64
    public let defaultMaxTokens: Int
    public let defaultMaxInputChars: Int
    let backend: ModelBackend
    let distribution: ModelDistribution

    init(
        id: String,
        displayName: String,
        repo: String,
        family: ModelFamily,
        estimatedBytes: UInt64,
        defaultMaxTokens: Int,
        defaultMaxInputChars: Int,
        backend: ModelBackend = .mlx,
        distribution: ModelDistribution = .repositorySnapshot
    ) {
        self.id = id
        self.displayName = displayName
        self.repo = repo
        self.family = family
        self.estimatedBytes = estimatedBytes
        self.defaultMaxTokens = defaultMaxTokens
        self.defaultMaxInputChars = defaultMaxInputChars
        self.backend = backend
        self.distribution = distribution
    }
}

public enum ModelCatalog {
    public static let entries: [ModelCatalogEntry] = [
        ModelCatalogEntry(id: "gemma-e4b-4bit", displayName: "Gemma 4 E4B (4-bit)",
            repo: "mlx-community/gemma-4-e4b-it-4bit", family: .gemma,
            estimatedBytes: 4_900_000_000, defaultMaxTokens: 2048, defaultMaxInputChars: 1500),
        ModelCatalogEntry(id: "gemma-e2b-4bit", displayName: "Gemma 4 E2B (4-bit)",
            repo: "mlx-community/gemma-4-e2b-it-4bit", family: .gemma,
            estimatedBytes: 3_600_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 700),
        ModelCatalogEntry(id: "hymt2-4bit", displayName: "Hy-MT2 1.8B (4-bit · 翻译专用)",
            repo: "mlx-community/Hy-MT2-1.8B-4bit", family: .hunyuanMT2,
            estimatedBytes: 1_100_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 1500),
        ModelCatalogEntry(id: "hymt2-8bit", displayName: "Hy-MT2 1.8B (8-bit · 翻译专用)",
            repo: "mlx-community/Hy-MT2-1.8B-8bit", family: .hunyuanMT2,
            estimatedBytes: 1_900_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 1500),
        ModelCatalogEntry(
            id: "hymt2-1.25bit",
            displayName: "Hy-MT2 1.8B（1.25-bit · 轻量版）",
            repo: "AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF",
            family: .hunyuanMT2,
            estimatedBytes: 461_860_800,
            defaultMaxTokens: 1024,
            defaultMaxInputChars: 1500,
            backend: .llamaGGUF(.stq1_0),
            distribution: .singleFile(SingleFileDistribution(
                fileName: "Hy-MT2-1.8B-1.25bit-v2.gguf",
                huggingFaceRevision: "0989912c0cc2d3edeeecd76171d1c7d94ee17255",
                modelScopeRevision: "2d3896c601bb165415669c31e8cf43c2554e7900",
                bytes: 461_860_800,
                sha256: "13a33fc4f72d5c92c439a65fd343696de4ccd0485bca84de2712bc0d8cc4e773"
            ))
        ),
        ModelCatalogEntry(
            id: "hymt2-2bit",
            displayName: "Hy-MT2 1.8B（2-bit · 均衡版）",
            repo: "AngelSlim/Hy-MT2-1.8B-2Bit-GGUF",
            family: .hunyuanMT2,
            estimatedBytes: 600_534_976,
            defaultMaxTokens: 1024,
            defaultMaxInputChars: 1500,
            backend: .llamaGGUF(.q2_0c),
            distribution: .singleFile(SingleFileDistribution(
                fileName: "Hy-MT2-1.8B-2bit-v2.gguf",
                huggingFaceRevision: "2245b9ea2bdd68a67b21b44db9564e7d32fc3bc6",
                modelScopeRevision: "6689e68668273c14fb5a45bd04ffe12e0601077b",
                bytes: 600_534_976,
                sha256: "ae35b1ee4e4a12011e8105d5e7e2bd10f0c4b4e09320367274922184c0831c95"
            ))
        ),
    ]

    public static func entry(id: String) -> ModelCatalogEntry? {
        entries.first { $0.id == id }
    }
}
