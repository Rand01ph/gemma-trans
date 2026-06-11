import Foundation
import LiteRTLM

public actor TranslationEngine: TranslationService {
    private let settings: AppSettings
    private var engine: Engine?
    private var lastGeneration: Task<Void, Never>?
    private var activeGenerations = 0
    private let detector = LanguageDetector()
    private var resolvedTuning: EngineTuning?

    /// 设置页展示用（actor 属性，外部 await 访问）
    public var currentTuning: EngineTuning? { resolvedTuning }

    /// 是否有生成正在排队或进行（去抖用：避免热键连按在串行队列里堆积，导致可见浮窗长时间挨饿）
    public var isGenerating: Bool { activeGenerations > 0 }

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var isReady: Bool { engine != nil }

    /// 加载模型（启动时调用一次；失败抛错，调用方负责状态展示）
    public func load() async throws {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaTrans").path
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let tuning: EngineTuning
        if settings.autoTuning {
            let modelSize = ((try? FileManager.default.attributesOfItem(atPath: settings.modelPath))?[.size] as? NSNumber)
                .map(\.uint64Value) ?? (4 << 30)
            tuning = EngineTuning.recommended(
                physicalMemory: SystemMemory.physical(),
                availableMemory: SystemMemory.available(),
                modelFileSize: modelSize
            )
            GTLog.info("auto tuning: kv=\(tuning.maxNumTokens) input=\(tuning.maxInputChars) " +
                       "(ram=\(SystemMemory.physical() >> 30)GB avail=\((SystemMemory.available() ?? 0) >> 30)GB)")
        } else {
            tuning = EngineTuning(maxNumTokens: settings.manualMaxNumTokens, maxInputChars: settings.maxInputChars)
            GTLog.info("manual tuning: kv=\(tuning.maxNumTokens) input=\(tuning.maxInputChars)")
        }
        resolvedTuning = tuning

        let config = try EngineConfig(
            modelPath: settings.modelPath,
            backend: .gpu,
            maxNumTokens: tuning.maxNumTokens,
            cacheDir: cacheDir
        )
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        self.engine = engine
    }

    public func translate(_ text: String, target: String?) async throws -> TranslationStreamResult {
        guard let engine else { throw TranslationError.modelNotLoaded }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        let maxChars = resolvedTuning?.maxInputChars ?? settings.maxInputChars
        let truncated = trimmed.count > maxChars
        let input = truncated ? String(trimmed.prefix(maxChars)) : trimmed
        let plan = detector.plan(for: input, target: target, settings: settings)
        let prompt = PromptBuilder.userPrompt(text: input, target: plan.target)

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let previous = lastGeneration
        activeGenerations += 1
        lastGeneration = Task {
            await previous?.value  // 串行：LiteRT 单飞，等上一个生成自然结束
            await engine.generate(prompt: prompt, system: PromptBuilder.systemPrompt, into: continuation)
            self.generationFinished()
        }
        return TranslationStreamResult(
            detected: plan.detected, target: plan.target, truncated: truncated, chunks: stream
        )
    }

    private func generationFinished() {
        activeGenerations -= 1
    }
}

extension Engine {
    /// 在 Engine actor 隔离域内完成整次生成——Conversation 非 Sendable，不能离开该域。
    func generate(
        prompt: String, system: String,
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        // 注意：不在循环内打断 LiteRT（conversation.cancel / 提前 break 会污染共享引擎，
        // 导致紧随其后的真生成产不出 token）。被取代的请求在 translate() 里于生成前就跳过了，
        // 真正在飞的这一次让它自然跑完——消费方已离开时 yield 自动丢弃，无害。
        do {
            let conversation = try createConversation(
                with: ConversationConfig(systemMessage: Message(system, role: .system))
            )
            for try await chunk in conversation.sendMessageStream(Message(prompt)) {
                continuation.yield(chunk.toString)
            }
            continuation.finish()
        } catch {
            GTLog.error("generation failed: \(error)")
            continuation.finish(throwing: error)
        }
    }
}
