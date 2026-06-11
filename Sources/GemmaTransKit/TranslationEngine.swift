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

    /// 加载模型（首次自动下载，progress 回调驱动 UI 显示百分比 + 已下/总字节量）
    /// - Parameter cacheDirectory: 模型缓存目录。非 nil（iOS/CLI）走自研 ModelDownloader
    ///   （双源 + 断点续传 + 字节级进度），iOS 传 App Group 容器目录使主 app 与翻译扩展
    ///   共享同一份模型文件；nil（macOS）走默认目录三级策略（见 load 内注释）：
    ///   新快照 → legacy HF 缓存（存量用户不重下）→ 自研下载器。
    /// - Parameter modelSource: 下载源。约束：国内网络 huggingface.co（Xet CDN）
    ///   不可达且 hf-mirror 已失效，设置页开关切 ModelScope 国内源。
    /// - Parameter tuningOverride: 非 nil 时直接采用，跳过 autoTuning/manual 推导。
    ///   iOS 用它固定 E2B 档——autoTuning 在 16GB 设备会选 E4B，与 iOS 侧固定的
    ///   E2B 仓库目录判定错位；nil 时行为与既有 macOS 调用完全一致。
    public func load(
        cacheDirectory: URL? = nil,
        modelSource: ModelSource = .huggingFace,
        tuningOverride: EngineTuning? = nil,
        progress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws {
        let tuning: EngineTuning
        if let tuningOverride {
            tuning = tuningOverride
            GTLog.info("override tuning: variant=\(tuning.variant.rawValue) maxTokens=\(tuning.maxTokens) input=\(tuning.maxInputChars)")
        } else if settings.autoTuning {
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
        // repo 由 variant 推导（与 EngineHolder 的 tuningOverride 构成 variant↔repo 名不变量）
        let repo = switch tuning.variant {
        case .gemma4E4B4bit: "mlx-community/gemma-4-e4b-it-4bit"
        case .gemma4E2B4bit: "mlx-community/gemma-4-e2b-it-4bit"
        }
        let loaded: ModelContainer
        if let cacheDirectory {
            // 自研下载路径（iOS/CLI 显式传目录）：快照不完整才触发下载，下载源按 modelSource 切换
            let snapshotDir = ModelDownloader.snapshotDirectory(in: cacheDirectory, repo: repo)
            if !ModelDownloader.isComplete(snapshotDir) {
                _ = try await ModelDownloader.download(
                    repo: repo, from: modelSource, into: cacheDirectory, progress: progress)
            }
            // 本地目录加载：EOS 等生成配置由快照内 generation_config.json 提供
            loaded = try await loadModelContainer(
                from: snapshotDir, using: #huggingFaceTokenizerLoader())
        } else {
            // macOS 默认路径三级策略：
            // 1. 新快照已完整 → 直接本地加载（新装用户经自研下载器落盘后的常态）；
            // 2. legacy HF 缓存已有该仓库 → 维持原 HF 宏路径离线加载——存量用户的模型
            //    在 ~/.cache/huggingface 里，强切新目录会让他们白下 GB 级权重；
            // 3. 都没有 → 自研 ModelDownloader 下载到默认目录后本地加载。不再走
            //    HubClient 下载（其进度回调在大文件期间长期不动 + HF Xet CDN 国内被墙）。
            let base = Self.defaultModelDirectory()
            let snapshotDir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
            if ModelDownloader.isComplete(snapshotDir) {
                loaded = try await loadModelContainer(
                    from: snapshotDir, using: #huggingFaceTokenizerLoader())
            } else if Self.legacyHFCacheHasModel(repo: repo) {
                loaded = try await #huggingFaceLoadModelContainer(configuration: configuration) { p in
                    // HF 宏路径只有比例没有字节数：completed/total 置 nil，UI 退化为只显示百分比
                    progress(DownloadProgress(fraction: p.fractionCompleted))
                }
            } else {
                let dir = try await ModelDownloader.download(
                    repo: repo, from: modelSource, into: base, progress: progress)
                loaded = try await loadModelContainer(
                    from: dir, using: #huggingFaceTokenizerLoader())
            }
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

    /// macOS 默认模型目录：~/Library/Application Support/GemmaTrans/models（自动建目录）
    private static func defaultModelDirectory() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaTrans/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// legacy HF 缓存（HubClient 默认路径）是否已有该仓库：目录存在且非空。
    /// 只看目录非空不做完整性校验——旧路径没有完成标记，宽判保住存量用户离线加载；
    /// 若旧缓存实际损坏，宏路径加载会失败并走上层重试/报错，不会静默吞掉。
    /// NSHomeDirectory：iOS 无 homeDirectoryForCurrentUser；沙盒下与 HF 宏展开 ~ 同源。
    private static func legacyHFCacheHasModel(repo: String) -> Bool {
        let dir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
            .appendingPathComponent(
                "models--\(repo.replacingOccurrences(of: "/", with: "--"))", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }
}
