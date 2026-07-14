import Foundation

public struct ResolvedModel: Sendable, Equatable {
    public let entry: ModelCatalogEntry
    public let tuning: EngineTuning
}

public enum ActiveModelResolver {
    public static func resolve(
        selectedID: String,
        parameterSettings: AppSettings = AppSettings()
    ) -> ResolvedModel? {
        guard let entry = ModelCatalog.entry(id: selectedID) else { return nil }
        // 显式选择只决定模型；参数自动配置使用 entry 建议值，关闭后使用用户手动上限。
        // variant 字段仅 Gemma 加载路径用到，
        // 非 Gemma family 时填一个占位（.gemma4E2B4bit），加载分发以 entry.family 为准。
        let variant: ModelVariant = entry.id == "gemma-e4b-4bit" ? .gemma4E4B4bit : .gemma4E2B4bit
        let maxTokens = parameterSettings.autoTuning
            ? entry.defaultMaxTokens
            : parameterSettings.manualMaxTokens
        let maxInputChars = parameterSettings.autoTuning
            ? entry.defaultMaxInputChars
            : parameterSettings.maxInputChars
        let tuning = EngineTuning(variant: variant,
            maxTokens: maxTokens, maxInputChars: maxInputChars)
        return ResolvedModel(entry: entry, tuning: tuning)
    }
}
