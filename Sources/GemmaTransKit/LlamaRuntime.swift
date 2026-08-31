import Foundation

#if os(macOS)
import LlamaRuntime
#endif

enum LlamaRuntimeError: Error, LocalizedError, Sendable, Equatable {
    case unavailablePlatform
    case modelLoad(String)
    case generationSetup(String)
    case generation(String)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .unavailablePlatform:
            "该模型仅支持 macOS Apple Silicon。"
        case .modelLoad(let message):
            "GGUF 模型加载失败：\(message)"
        case .generationSetup(let message):
            "GGUF 生成初始化失败：\(message)"
        case .generation(let message):
            "GGUF 生成失败：\(message)"
        case .invalidUTF8:
            "GGUF 输出包含不完整的 UTF-8 字节。"
        }
    }
}

struct LlamaGenerationMetrics: Sendable, Equatable {
    let promptTokens: Int
    let generatedTokens: Int
    let firstTokenSeconds: Double
    let totalSeconds: Double
    let tokensPerSecond: Double
}

struct UTF8StreamAccumulator: Sendable {
    private(set) var pending = Data()

    mutating func append<S: Sequence>(_ bytes: S) -> String? where S.Element == UInt8 {
        pending.append(contentsOf: bytes)
        guard let text = String(data: pending, encoding: .utf8) else { return nil }
        pending.removeAll(keepingCapacity: true)
        return text
    }

    func finish() throws {
        guard pending.isEmpty else { throw LlamaRuntimeError.invalidUTF8 }
    }
}

/// 两款策展 GGUF 的唯一 Swift 运行时入口。C 指针始终留在 actor 内；每次生成清空 KV，
/// 生成循环逐步检查 Task 取消，流终止后立即释放 sampler 和本轮临时状态。
actor LlamaRuntime {
#if os(macOS)
    /// Swift 6 的 actor deinit 是 nonisolated；用私有 RAII 盒保证即使加载后预热失败，
    /// 指针也会随 actor/属性释放，且盒本身从不离开本 actor。
    private final class ModelHandle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { gt_llama_model_free(pointer) }
    }

    private var model: ModelHandle?
#endif

    var isLoaded: Bool {
#if os(macOS)
        model != nil
#else
        false
#endif
    }

    init() {
#if os(macOS)
        gt_llama_backend_initialize()
#endif
    }

    func load(fileURL: URL, quantization: GGUFQuantization) throws {
#if os(macOS)
        unload()
        let active = ProcessInfo.processInfo.activeProcessorCount
        let threads = min(8, max(2, active - 2))
        let cQuantization: gt_llama_quantization = switch quantization {
        case .stq1_0: GT_LLAMA_QUANTIZATION_STQ1_0
        case .q2_0c: GT_LLAMA_QUANTIZATION_Q2_0C
        }
        let config = gt_llama_model_config(
            context_size: 4_096,
            batch_size: 512,
            thread_count: Int32(threads),
            quantization: cQuantization
        )
        var error = Self.errorBuffer()
        let loaded = fileURL.path.withCString { path in
            error.withUnsafeMutableBufferPointer { buffer in
                gt_llama_model_load(path, config, buffer.baseAddress, buffer.count)
            }
        }
        guard let loaded else {
            throw LlamaRuntimeError.modelLoad(Self.errorMessage(error))
        }
        model = ModelHandle(loaded)
        GTLog.info("llama model loaded: \(fileURL.lastPathComponent), threads=\(threads), CPU/NEON")
#else
        throw LlamaRuntimeError.unavailablePlatform
#endif
    }

    /// 以真实 chat template 跑一 token，提前完成页表建立和内核热身。
    func warmup() throws {
#if os(macOS)
        _ = try generate(
            userPrompt: PromptBuilder.userPrompt(text: "你好", target: "en"),
            maxTokens: 1,
            onChunk: { _ in }
        )
#else
        throw LlamaRuntimeError.unavailablePlatform
#endif
    }

    func generate(
        userPrompt: String,
        maxTokens: Int,
        onChunk: @Sendable (String) -> Void
    ) throws -> LlamaGenerationMetrics {
#if os(macOS)
        guard let model else { throw TranslationError.modelNotLoaded }
        try Task.checkCancellation()

        let sampling = gt_llama_sampling_config(
            max_tokens: Int32(min(1_024, max(1, maxTokens))),
            top_k: 20,
            top_p: 0.6,
            temperature: 0.7,
            repetition_penalty: 1.05,
            seed: 42
        )
        var error = Self.errorBuffer()
        let generation = userPrompt.withCString { prompt in
            error.withUnsafeMutableBufferPointer { buffer in
                gt_llama_generation_begin(
                    model.pointer, prompt, sampling, buffer.baseAddress, buffer.count)
            }
        }
        guard let generation else {
            throw LlamaRuntimeError.generationSetup(Self.errorMessage(error))
        }
        defer { gt_llama_generation_free(generation) }

        var tokenBuffer = [UInt8](repeating: 0, count: 4_096)
        var utf8 = UTF8StreamAccumulator()
        while true {
            try Task.checkCancellation()
            var length = 0
            error = Self.errorBuffer()
            let result = tokenBuffer.withUnsafeMutableBufferPointer { output in
                error.withUnsafeMutableBufferPointer { errorBuffer in
                    gt_llama_generation_step(
                        generation,
                        output.baseAddress,
                        output.count,
                        &length,
                        errorBuffer.baseAddress,
                        errorBuffer.count
                    )
                }
            }
            switch result {
            case GT_LLAMA_STEP_PROGRESS:
                continue
            case GT_LLAMA_STEP_TOKEN:
                if length > 0 {
                    // 不按 token 强行造 String：中文码点可能横跨多个 token piece。
                    if let text = utf8.append(tokenBuffer.prefix(length)) {
                        onChunk(text)
                    }
                }
            case GT_LLAMA_STEP_EOG:
                try utf8.finish()
                let metrics = gt_llama_generation_metrics(generation)
                return LlamaGenerationMetrics(
                    promptTokens: Int(metrics.prompt_tokens),
                    generatedTokens: Int(metrics.generated_tokens),
                    firstTokenSeconds: metrics.first_token_seconds,
                    totalSeconds: metrics.total_seconds,
                    tokensPerSecond: metrics.tokens_per_second
                )
            default:
                throw LlamaRuntimeError.generation(Self.errorMessage(error))
            }
        }
#else
        throw LlamaRuntimeError.unavailablePlatform
#endif
    }

    func unload() {
#if os(macOS)
        if model != nil {
            model = nil
            GTLog.info("llama model unloaded")
        }
#endif
    }

#if os(macOS)
    private static func errorBuffer() -> [CChar] {
        [CChar](repeating: 0, count: 1_024)
    }

    private static func errorMessage(_ buffer: [CChar]) -> String {
        buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress, base.pointee != 0 else {
                return "unknown runtime error"
            }
            return String(cString: base)
        }
    }
#endif
}
