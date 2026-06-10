import Foundation
import LiteRTLM

public actor TranslationEngine: TranslationService {
    private let settings: AppSettings
    private var engine: Engine?
    private var lastGeneration: Task<Void, Never>?
    private let detector = LanguageDetector()

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var isReady: Bool { engine != nil }

    /// 加载模型（启动时调用一次；失败抛错，调用方负责状态展示）
    public func load() async throws {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaTrans").path
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let config = try EngineConfig(
            modelPath: settings.modelPath,
            backend: .gpu,
            maxNumTokens: 4096,
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

        let truncated = trimmed.count > settings.maxInputChars
        let input = truncated ? String(trimmed.prefix(settings.maxInputChars)) : trimmed
        let plan = detector.plan(for: input, target: target, settings: settings)
        let prompt = PromptBuilder.userPrompt(text: input, target: plan.target)

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let previous = lastGeneration
        lastGeneration = Task {
            await previous?.value  // 串行：等上一个生成完
            await engine.generate(prompt: prompt, system: PromptBuilder.systemPrompt, into: continuation)
        }
        return TranslationStreamResult(
            detected: plan.detected, target: plan.target, truncated: truncated, chunks: stream
        )
    }
}

extension Engine {
    /// 在 Engine actor 隔离域内完成整次生成——Conversation 非 Sendable，不能离开该域。
    func generate(
        prompt: String, system: String,
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            let conversation = try createConversation(
                with: ConversationConfig(systemMessage: Message(system, role: .system))
            )
            for try await chunk in conversation.sendMessageStream(Message(prompt)) {
                continuation.yield(chunk.toString)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
