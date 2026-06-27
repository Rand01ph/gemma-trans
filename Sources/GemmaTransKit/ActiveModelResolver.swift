import Foundation

public struct ResolvedModel: Sendable, Equatable {
    public let entry: ModelCatalogEntry
    public let tuning: EngineTuning
}

public enum ActiveModelResolver {
    public static func resolve(
        selectedID: String, physicalMemory: UInt64, availableMemory: UInt64?
    ) -> ResolvedModel {
        // Auto 或未知 id：按内存选 Gemma（沿用既有分档），映射到对应 catalog 条目
        if selectedID == ModelCatalog.autoID || ModelCatalog.entry(id: selectedID) == nil {
            let t = EngineTuning.recommended(
                physicalMemory: physicalMemory, availableMemory: availableMemory)
            let id = (t.variant == .gemma4E4B4bit) ? "gemma-e4b-4bit" : "gemma-e2b-4bit"
            return ResolvedModel(entry: ModelCatalog.entry(id: id)!, tuning: t)
        }
        // 显式选择：用 entry 默认参数构造 tuning。variant 字段仅 Gemma 加载路径用到，
        // 非 Gemma family 时填一个占位（.gemma4E2B4bit），加载分发以 entry.family 为准。
        let e = ModelCatalog.entry(id: selectedID)!
        let variant: ModelVariant = (e.id == "gemma-e4b-4bit") ? .gemma4E4B4bit : .gemma4E2B4bit
        let tuning = EngineTuning(variant: variant,
            maxTokens: e.defaultMaxTokens, maxInputChars: e.defaultMaxInputChars)
        return ResolvedModel(entry: e, tuning: tuning)
    }
}
