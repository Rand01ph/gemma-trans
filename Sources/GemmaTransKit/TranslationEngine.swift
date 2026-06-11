import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

public actor TranslationEngine: TranslationService {
    private let settings: AppSettings
    private var model: ModelContainer?
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

    public var isReady: Bool { model != nil }

    /// 加载模型（首次自动从 HuggingFace 下载，progress 回调驱动 UI 显示百分比）
    public func load(progress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        let tuning: EngineTuning
        if settings.autoTuning {
            tuning = EngineTuning.recommended(
                physicalMemory: SystemMemory.physical(),
                availableMemory: SystemMemory.available()
            )
            GTLog.info("auto tuning: variant=\(tuning.variant.rawValue) maxTokens=\(tuning.maxTokens) input=\(tuning.maxInputChars) " +
                       "(ram=\(SystemMemory.physical() >> 30)GB avail=\((SystemMemory.available() ?? 0) >> 30)GB)")
        } else {
            tuning = EngineTuning(
                variant: .gemma4E4B4bit,
                maxTokens: settings.manualMaxTokens,
                maxInputChars: settings.maxInputChars
            )
            GTLog.info("manual tuning: maxTokens=\(tuning.maxTokens) input=\(tuning.maxInputChars)")
        }
        resolvedTuning = tuning

        let configuration =
            switch tuning.variant {
            case .gemma4E4B4bit: LLMRegistry.gemma4_e4b_it_4bit
            case .gemma4E2B4bit: LLMRegistry.gemma4_e2b_it_4bit
            }
        let loaded = try await #huggingFaceLoadModelContainer(configuration: configuration) { p in
            progress(p.fractionCompleted)
        }
        // 预热：首次生成触发 Metal 内核编译（冷启可超 30s，曾致首单超时 500）。
        // 在置 ready 前用 1-token 生成把编译做完，用户首单即快。
        let warmup = ChatSession(loaded, generateParameters: GenerateParameters(maxTokens: 1))
        _ = try? await warmup.respond(to: "hi")
        model = loaded
        GTLog.info("mlx model loaded+warmed: \(configuration.name)")
    }

    public func translate(_ text: String, target: String?) async throws -> TranslationStreamResult {
        guard let model else { throw TranslationError.modelNotLoaded }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        let maxChars = resolvedTuning?.maxInputChars ?? settings.maxInputChars
        let truncated = trimmed.count > maxChars
        let input = truncated ? String(trimmed.prefix(maxChars)) : trimmed
        let plan = detector.plan(for: input, target: target, settings: settings)
        let prompt = PromptBuilder.userPrompt(text: input, target: plan.target)
        let maxTokens = resolvedTuning?.maxTokens ?? 2048

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let previous = lastGeneration
        activeGenerations += 1
        lastGeneration = Task {
            await previous?.value  // 串行：GPU 单飞，等上一个生成自然结束
            do {
                // 每次翻译一次性会话：无历史、系统指令固定
                let session = ChatSession(
                    model,
                    instructions: PromptBuilder.systemPrompt,
                    generateParameters: GenerateParameters(maxTokens: maxTokens)
                )
                for try await chunk in session.streamResponse(to: prompt) {
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                GTLog.error("generation failed: \(error)")
                continuation.finish(throwing: error)
            }
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
