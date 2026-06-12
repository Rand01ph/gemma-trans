import AppIntents
import GemmaTransKit
import os

/// 快捷指令生态里的本地大模型处理节点：任意「文本 + 指令」任务，
/// 不联网、不要 API key、文本不离开设备。翻译是它的第一个特例（TranslateIntent）。
///
/// **`ReturnsValue<String>` 是设计灵魂**：输出作为变量回传快捷指令，可直接喂给
/// 「添加提醒事项 / 存入备忘录 / 发送通知」等后续动作——自动化由用户拼装，
/// 我们不造待办轮子。dialog 同时原地弹一份结果（手动触发场景可见）。
///
/// 执行体复用 TranslateIntent 的后台模式（理由详见该文件注释）：
/// ① `openAppWhenRun = false`：后台拉起主 app 进程执行，不切走前台 app；
/// ② useCPU：iPhone 全系后台 GPU 不可用，CPU 不受后台限制；
/// ③ 自建临时引擎冷加载：不复用前台 EngineHolder，避免 MLX 进程级
///    全局默认设备（GPU↔CPU）在前后台之间冲突。
struct ProcessTextIntent: AppIntent {
    static let title: LocalizedStringResource = "本地 AI 处理"
    static let description = IntentDescription("用本地 Gemma 模型按指令处理文本（不联网）")
    // 关键：false = 后台拉起主 app 进程执行，不切走前台 app
    static let openAppWhenRun = false

    @Parameter(title: "文本") var text: String

    @Parameter(title: "任务") var task: ProcessTaskEntity

    @Parameter(
        title: "自定义指令",
        description: "非空时优先生效，覆盖「任务」自带的指令；留空则用「任务」的指令")
    var instruction: String?

    /// 后台 CPU 推理的输入上限（短信/段落级），与引擎 tuningOverride 的 maxInputChars 一致
    private static let maxInputChars = 700

    @MainActor
    func perform() async throws
        -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            guard ModelStore.modelDownloaded else {
                return .result(value: "", dialog: "模型未下载——请先打开 GemmaTrans 完成下载")
            }

            // 指令解析：instruction 参数非空即优先于 task 自带的指令（保持简单，不引入占位实体）
            let resolvedInstruction: String
            if let instruction,
               !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolvedInstruction = instruction
            } else {
                resolvedInstruction = task.instruction
            }

            // 超长截断：注记只进 dialog、不进回传值——回传值要直接喂提醒事项标题等
            // 后续动作，不能被注记污染（设计文档：「超长截断并在 dialog 注明」）
            let truncated = text.count > Self.maxInputChars
            let input = truncated ? String(text.prefix(Self.maxInputChars)) : text

            let engine = TranslationEngine(
                settings: AppSettings.load(suiteName: ModelStore.settingsSuite))

            let t0 = Date()
            // tuningOverride 固定 E2B 档并把 maxInputChars 限到 700（后台 CPU 内存/时延约束）
            try await engine.load(
                cacheDirectory: ModelStore.cacheDirectory,
                tuningOverride: EngineTuning(
                    variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: Self.maxInputChars),
                useCPU: true)
            let loadElapsed = Date().timeIntervalSince(t0)

            let t1 = Date()
            let out = try await engine.process(input, instruction: resolvedInstruction)
            let processElapsed = Date().timeIntervalSince(t1)

            // 正式版不记录用户文本与指令内容（隐私，与 TranslateIntent 一致），只留任务 id 与耗时
            GTLog.info("[process-intent] task=\(task.id) " +
                       "load=\(String(format: "%.1f", loadElapsed))s " +
                       "process=\(String(format: "%.1f", processElapsed))s")

            let dialogText = truncated ? out + "\n（输入超长，已截断）" : out
            return .result(value: out, dialog: IntentDialog(stringLiteral: dialogText))
        } catch {
            GTLog.error("[process-intent] failed: \(error)")
            // 不抛错：自动化链路里硬失败会中断整条快捷指令；
            // 回传空串让用户可加「如果=空则停止」分支，dialog 留人话错误
            return .result(value: "", dialog: IntentDialog(stringLiteral: "处理失败：\(error)"))
        }
    }
}
