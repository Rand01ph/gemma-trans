import AppIntents
import GemmaTransKit
import os

/// 分享 / 快捷指令入口的后台翻译（主交互）。
///
/// ① `openAppWhenRun = false`：在分享面板或快捷指令里触发时，系统后台拉起主 app
///    进程执行 `perform()`，不把用户从当前 app 切走——选中文字 → 翻译 → 原地弹
///    dialog 译文。主 app 进程持有 increased-memory-limit，能加载本地模型；翻译 UI
///    扩展进程仅 221MB 额度跑不动，故走主 app。
///
/// ② 用 CPU 模式：iPhone 全系后台 GPU 不可用（`BGTaskScheduler.supportedResources`
///    不含 `.gpu`，MLX 默认 Metal 后台被 accessRevoked 崩溃），CPU 不受后台限制。
///
/// ③ 自建临时引擎冷加载：后台进程生命周期由系统调度、不可控，不复用前台 EngineHolder
///    的 GPU 引擎——避免 MLX 进程级全局默认设备（GPU↔CPU）在前后台之间冲突。
struct TranslateIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译文本"
    static let description = IntentDescription("用本地 Gemma 模型翻译文本（不联网）")
    // 关键：false = 后台拉起主 app 进程执行，不切走前台 app
    static let openAppWhenRun = false

    @Parameter(title: "文本") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            guard ModelStore.modelDownloaded else {
                return .result(dialog: "模型未下载——请先打开 GemmaTrans 完成下载")
            }
            let engine = TranslationEngine(
                settings: AppSettings.load(suiteName: ModelStore.settingsSuite))

            let t0 = Date()
            // tuningOverride 固定 E2B 档并把 maxInputChars 限到 700（后台 CPU 内存/时延约束）
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

            // 正式版不记录用户文本内容（隐私），只留语向与耗时
            GTLog.info("[intent] \(result.detected)→\(result.target) " +
                       "load=\(String(format: "%.1f", loadElapsed))s " +
                       "translate=\(String(format: "%.1f", translateElapsed))s")
            return .result(dialog: IntentDialog(stringLiteral: out))
        } catch {
            GTLog.error("[intent] failed: \(error)")
            return .result(dialog: IntentDialog(stringLiteral: "翻译失败：\(error)"))
        }
    }
}
