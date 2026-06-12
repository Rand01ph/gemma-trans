import AppIntents
import GemmaTransKit
import os

/// 快捷指令入口：后台拉起主 app 进程执行翻译（主交互）。
/// 翻译 UI 扩展进程额度仅 221MB 跑不动模型（spike 真机实测），
/// 主 app 进程有 increased-memory-limit，模型在这里加载才安全。
struct TranslateIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译文本"
    static let description = IntentDescription("用本地 Gemma 模型翻译文本（不联网）")
    // 关键：false = 后台拉起主 app 进程执行，不切走前台 app
    static let openAppWhenRun = false

    @Parameter(title: "文本") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // spike：真实后台 CPU 路径验证。后台 GPU 在 iPhone 全系不可用
        // （BGTaskScheduler.supportedResources 不含 .gpu，MLX 默认 Metal 后台被
        // accessRevoked 崩溃），但 CPU 不受后台限制。故这里不走 EngineHolder（GPU），
        // 自建临时 CPU 引擎，实测后台进程额度 + load + translate 耗时。
        do {
            // 后台进程内存额度（决定后台跑 3.6GB 模型可行性）
            GTLog.info("[spike-cpu-intent] mem=\(os_proc_available_memory() / 1_048_576)MB")
            guard ModelStore.modelDownloaded else {
                return .result(dialog: "模型未下载——请先打开 GemmaTrans 完成下载")
            }
            let engine = TranslationEngine(
                settings: AppSettings.load(suiteName: ModelStore.settingsSuite))

            let t0 = Date()
            try await engine.load(
                cacheDirectory: ModelStore.cacheDirectory,
                tuningOverride: EngineTuning(
                    variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700),
                useCPU: true)
            let loadElapsed = Date().timeIntervalSince(t0)

            let t1 = Date()
            let result = try await engine.translate(text, target: nil)
            let out = try await result.fullText()
            let translateElapsed = Date().timeIntervalSince(t1)

            GTLog.info("[spike-cpu-intent] mem=\(os_proc_available_memory() / 1_048_576)MB " +
                       "load=\(String(format: "%.1f", loadElapsed))s " +
                       "translate=\(String(format: "%.1f", translateElapsed))s")
            return .result(dialog: IntentDialog(stringLiteral: out))
        } catch {
            GTLog.error("[spike-cpu-intent] failed: \(error)")
            return .result(dialog: IntentDialog(stringLiteral: "翻译失败：\(error)"))
        }
    }
}
