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
        // spike 记录：后台进程内存额度（决定后台跑模型可行性）
        GTLog.info("[intent] available memory: \(os_proc_available_memory() / 1_048_576) MB")
        guard ModelStore.modelDownloaded else {
            return .result(dialog: "模型未下载——请先打开 GemmaTrans 完成下载")
        }
        let t0 = Date()
        EngineHolder.shared.loadIfDownloaded()
        while EngineHolder.shared.status != .ready {
            if case .failed(let msg) = EngineHolder.shared.status {
                return .result(dialog: IntentDialog(stringLiteral: "引擎加载失败：\(msg)"))
            }
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(150))
        }
        guard let engine = EngineHolder.shared.engine else {
            return .result(dialog: "引擎不可用")
        }
        let result = try await engine.translate(text, target: nil)
        let out = try await result.fullText()
        GTLog.info("[intent] done load+translate in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        return .result(dialog: IntentDialog(stringLiteral: out))
    }
}
