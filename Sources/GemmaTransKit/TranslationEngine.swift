import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

public actor TranslationEngine: TranslationService {
    private let settings: AppSettings
    private var model: ModelContainer?
    private var lastGeneration: Task<Void, Never>?
    private var generationTasks: [UUID: Task<Void, Never>] = [:]
    private let detector = LanguageDetector()
    private var resolvedTuning: EngineTuning?
    /// 当前活跃模型的 family，决定 prompt 策略：Gemma 用 systemPrompt；Hy-MT2（混元）按其
    /// 推荐格式只发 user 指令、不用 system（spike 验证：无 system 译文最稳）。
    private var activeFamily: ModelFamily = .gemma

    /// 上一次生成的速度（生成 token 数 / 生成耗时），供 UI 观察性能；nil 表示尚无生成。
    public private(set) var lastTokensPerSecond: Double?

    /// 设置页展示用（actor 属性，外部 await 访问）
    public var currentTuning: EngineTuning? { resolvedTuning }

    /// 是否有生成正在排队或进行（去抖用：避免热键连按在串行队列里堆积，导致可见浮窗长时间挨饿）
    public var isGenerating: Bool { !generationTasks.isEmpty }

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var isReady: Bool { model != nil }

    /// 加载模型（首次自动下载，progress 回调驱动 UI 显示百分比 + 已下/总字节量）
    /// - Parameter cacheDirectory: 模型缓存目录。非 nil（iOS/CLI）走自研 ModelDownloader
    ///   （双源 + 断点续传 + 字节级进度），iOS 传 App Group 容器目录使主 app 与翻译扩展
    ///   共享同一份模型文件；nil（macOS）走默认目录三级策略（见 load 内注释）：
    ///   新快照 → legacy HF 缓存（存量用户不重下）→ 自研下载器。
    /// - Parameter modelSource: 可选固定下载源；nil 时 Hugging Face 优先、失败自动回退 ModelScope。
    /// - Parameter tuningOverride: 非 nil 时直接采用，跳过 autoTuning/manual 推导。
    ///   iOS 用它固定 E2B 档——autoTuning 在 16GB 设备会选 E4B，与 iOS 侧固定的
    ///   E2B 仓库目录判定错位；nil 时行为与既有 macOS 调用完全一致。
    /// - Parameter useCPU: spike 用。true 时把 MLX 全局默认设备切到 CPU，绕开后台 GPU
    ///   不可用（iPhone 全系 BGTaskScheduler.supportedResources 不含 .gpu，Metal 后台
    ///   被 accessRevoked 崩溃）。默认 false，行为与既有调用完全一致（GPU）。
    ///   setDefault 是进程级全局，actor 内设一次即可。
    public func load(
        cacheDirectory: URL? = nil,
        modelSource: ModelSource? = nil,
        tuningOverride: EngineTuning? = nil,
        useCPU: Bool = false,
        progress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws {
        if useCPU {
            // 进程级全局默认设备切 CPU。Device.setDefault 虽标 deprecated，但它是唯一
            // 真正翻转「全局默认」的 setter（写 _defaultDevice，被 TaskLocal 默认值
            // _resolveGlobalDefaultDevice() 读取，最终经 StreamOrDevice.default → CPU
            // stream 驱动算子）；withDefaultDevice 只能 scoped 到闭包，跨 actor 内
            // 生成 Task 包不住，故 spike 取全局 setter。
            MLX.Device.setDefault(device: MLX.Device(.cpu))
            GTLog.info("[spike-cpu] MLX device set to CPU")
        }
        let tuning: EngineTuning
        if let tuningOverride {
            tuning = tuningOverride
            GTLog.info("override tuning: variant=\(tuning.variant.rawValue) maxTokens=\(tuning.maxTokens) input=\(tuning.maxInputChars)")
        } else if settings.autoTuning {
            let auto = EngineTuning.recommended(
                physicalMemory: SystemMemory.physical(),
                availableMemory: SystemMemory.available()
            )
            GTLog.info("auto tuning: variant=\(auto.variant.rawValue) maxTokens=\(auto.maxTokens) input=\(auto.maxInputChars) " +
                       "(ram=\(SystemMemory.physical() >> 30)GB avail=\((SystemMemory.available() ?? 0) >> 30)GB)")
            // 本地优先纠偏仅对 cacheDirectory==nil（macOS 默认目录）路径生效：
            // 自定义目录（iOS/CLI）走 tuningOverride 不进此分支，且其本地缓存位置不同
            tuning = cacheDirectory == nil ? Self.preferLocalModel(over: auto) : auto
        } else {
            tuning = EngineTuning(
                variant: .gemma4E4B4bit,
                maxTokens: settings.manualMaxTokens,
                maxInputChars: settings.maxInputChars
            )
            GTLog.info("manual tuning: maxTokens=\(tuning.maxTokens) input=\(tuning.maxInputChars)")
        }
        activeFamily = .gemma
        resolvedTuning = tuning

        let configuration =
            switch tuning.variant {
            case .gemma4E4B4bit: LLMRegistry.gemma4_e4b_it_4bit
            case .gemma4E2B4bit: LLMRegistry.gemma4_e2b_it_4bit
            }
        let repo = Self.repoName(for: tuning.variant)
        let loaded: ModelContainer
        if let cacheDirectory {
            // 自研下载路径（iOS/CLI 显式传目录）：快照不完整才触发下载；未固定来源时自动换源
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
        await finishLoading(loaded, label: configuration.name)
    }

    /// 加载指定 ResolvedModel（按 entry.repo 下载/加载，按 entry.family 分发）。
    /// 所有既有调用方（EngineController / EngineHolder / CLI）继续使用旧签名，两者互不影响。
    /// - Parameter resolved: 已解析的模型条目 + 调优参数（由 ActiveModelResolver 产出）。
    /// - Parameter cacheDirectory: 非 nil 时走自研 ModelDownloader（iOS/CLI）；nil 时走 macOS 三级策略。
    ///   macOS 同样使用三级策略：新快照 → 旧版 HF 缓存 → 自研下载器，避免升级用户重下模型。
    /// - Parameter modelSource: 可选固定下载源；nil 时 Hugging Face 优先、失败自动回退 ModelScope。
    /// - Parameter useCPU: spike 用；true 时切 MLX 全局默认设备到 CPU。
    /// - Parameter progress: 下载进度回调。
    public func load(
        resolved: ResolvedModel,
        cacheDirectory: URL? = nil,
        modelSource: ModelSource? = nil,
        useCPU: Bool = false,
        progress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws {
        if useCPU {
            MLX.Device.setDefault(device: MLX.Device(.cpu))
            GTLog.info("[spike-cpu] MLX device set to CPU")
        }
        resolvedTuning = resolved.tuning
        activeFamily = resolved.entry.family
        GTLog.info("load(resolved:) entry=\(resolved.entry.id) repo=\(resolved.entry.repo) " +
                   "family=\(resolved.entry.family.rawValue)")

        let repo = resolved.entry.repo
        let base = cacheDirectory ?? Self.defaultModelDirectory()
        let snapshotDir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
        let canLoadLegacyGemma = cacheDirectory == nil
            && resolved.entry.family == .gemma
            && InstalledModels.legacyCacheHasModel(
                repo: repo,
                hub: InstalledModels.defaultLegacyHuggingFaceHub
            )
        if !ModelDownloader.isComplete(snapshotDir) && !canLoadLegacyGemma {
            _ = try await ModelDownloader.download(
                repo: repo, from: modelSource, into: base, progress: progress)
        }

        let loaded: ModelContainer
        switch resolved.entry.family {
        case .gemma:
            if canLoadLegacyGemma && !ModelDownloader.isComplete(snapshotDir) {
                let configuration = switch resolved.tuning.variant {
                case .gemma4E4B4bit: LLMRegistry.gemma4_e4b_it_4bit
                case .gemma4E2B4bit: LLMRegistry.gemma4_e2b_it_4bit
                }
                loaded = try await #huggingFaceLoadModelContainer(configuration: configuration) { p in
                    progress(DownloadProgress(fraction: p.fractionCompleted))
                }
            } else {
                loaded = try await loadModelContainer(
                    from: snapshotDir,
                    using: #huggingFaceTokenizerLoader()
                )
            }
        case .hunyuanMT2:
            // 混元架构不在 Swift MLXLLM 内置类型表，加载前注册自定义类型（幂等）。
            await registerHunyuanIfNeeded()
            loaded = try await loadModelContainer(from: snapshotDir, using: #huggingFaceTokenizerLoader())
        }

        await finishLoading(loaded, label: resolved.entry.repo)
    }

    /// 预热 + 置 ready + 回收缓冲。两个 load 入口共用。
    private func finishLoading(_ container: ModelContainer, label: String) async {
        // 预热：首次生成触发 Metal 内核编译（冷启可超 30s，曾致首单超时 500）。
        // 在置 ready 前用 1-token 生成把编译做完，用户首单即快。
        let warmup = ChatSession(container, generateParameters: GenerateParameters(maxTokens: 1))
        _ = try? await warmup.respond(to: "hi")
        model = container
        // 预热（1-token 生成）留下的临时缓冲在置 ready 后立即回收，让初始空闲态就精简；
        // 权重已在 model 中常驻，clearCache 不动它。
        MLX.Memory.clearCache()
        GTLog.info("mlx model loaded+warmed: \(label), " +
                   "active(权重)\(MLX.Memory.activeMemory >> 20)MB cache\(MLX.Memory.cacheMemory >> 20)MB")
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
        // Gemma 用固定系统指令；Hy-MT2 按推荐只发 user 指令（无 system）。
        // 先 capture 到局部，避免下面的 Task 闭包访问 actor 隔离的 activeFamily。
        let instructions = activeFamily == .gemma ? PromptBuilder.systemPrompt : nil

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let generationID = UUID()
        let previous = lastGeneration
        let generationTask = Task {
            await previous?.value  // 串行：GPU 单飞，等上一个生成自然结束
            defer { self.generationFinished(id: generationID) }
            do {
                try Task.checkCancellation()
                // 每次翻译一次性会话：无历史、系统指令固定
                // 翻译是确定性任务：默认温度 0.6 的采样随机性会偶尔走到「复述原文/跑偏」，
                // 降到 0.1（近贪心）让模型确定性遵循翻译指令。repetitionPenalty 抑制小模型复读。
                let session = ChatSession(
                    model,
                    instructions: instructions,
                    generateParameters: GenerateParameters(
                        maxTokens: maxTokens, temperature: 0.1, repetitionPenalty: 1.1)
                )
                for try await item in session.streamDetails(to: prompt, images: [], videos: []) {
                    try Task.checkCancellation()
                    switch item {
                    case .chunk(let text):
                        continuation.yield(text)
                    case .info(let info):
                        lastTokensPerSecond = info.tokensPerSecond
                        GTLog.info("mlx gen: \(info.generationTokenCount) tok, " +
                            String(format: "%.2fs, %.1f tok/s", info.generateTime, info.tokensPerSecond))
                    case .toolCall:
                        break
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                GTLog.error("generation failed: \(error)")
                continuation.finish(throwing: error)
            }
        }
        generationTasks[generationID] = generationTask
        lastGeneration = generationTask
        continuation.onTermination = { @Sendable [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.cancelGeneration(id: generationID) }
        }
        return TranslationStreamResult(
            detected: plan.detected, target: plan.target, truncated: truncated, chunks: stream
        )
    }

    /// 一次性 process 会话：按 instruction 处理 text，返回聚合结果。
    /// 复用串行队列、maxTokens 与翻译相同的 temperature/repetitionPenalty。
    /// 输入按 resolvedTuning.maxInputChars 截断；不走 LanguageDetector。
    public func process(_ text: String, instruction: String) async throws -> String {
        guard let model else { throw TranslationError.modelNotLoaded }
        // 通用文本处理只在通用模型（Gemma）上可靠；Hy-MT2 是翻译专用，喂任意指令易出烂结果，
        // 直接拒绝而非静默跑偏（采纳 Codex 审查）。
        guard activeFamily == .gemma else {
            throw TranslationError.modelNotSupported("当前为翻译专用模型，不支持通用文本处理，请切换到 Gemma")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        let maxChars = resolvedTuning?.maxInputChars ?? settings.maxInputChars
        let input = trimmed.count > maxChars ? String(trimmed.prefix(maxChars)) : trimmed
        let prompt = PromptBuilder.processUserPrompt(text: input, instruction: instruction)
        let maxTokens = resolvedTuning?.maxTokens ?? 2048
        let instructions = activeFamily == .gemma ? PromptBuilder.processSystemPrompt : nil

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let generationID = UUID()
        let previous = lastGeneration
        let generationTask = Task {
            await previous?.value
            defer { self.generationFinished(id: generationID) }
            do {
                try Task.checkCancellation()
                let session = ChatSession(
                    model,
                    instructions: instructions,
                    generateParameters: GenerateParameters(
                        maxTokens: maxTokens, temperature: 0.1, repetitionPenalty: 1.1)
                )
                for try await item in session.streamDetails(to: prompt, images: [], videos: []) {
                    try Task.checkCancellation()
                    switch item {
                    case .chunk(let text):
                        continuation.yield(text)
                    case .info(let info):
                        lastTokensPerSecond = info.tokensPerSecond
                        GTLog.info("mlx process: \(info.generationTokenCount) tok, " +
                            String(format: "%.2fs, %.1f tok/s", info.generateTime, info.tokensPerSecond))
                    case .toolCall:
                        break
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                GTLog.error("process generation failed: \(error)")
                continuation.finish(throwing: error)
            }
        }
        generationTasks[generationID] = generationTask
        lastGeneration = generationTask
        continuation.onTermination = { @Sendable [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.cancelGeneration(id: generationID) }
        }
        var out = ""
        for try await chunk in stream { out += chunk }
        try Task.checkCancellation()
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cancelGeneration(id: UUID) {
        generationTasks[id]?.cancel()
    }

    private func generationFinished(id: UUID) {
        generationTasks[id] = nil
        // 队列真正排空才回收：连续/排队生成（含 API 串行链）中途任务表不为空，
        // 故不会清掉马上要复用的缓冲、不抖动。clearCache 只把没人引用的空闲缓冲池
        // （上一轮 KV cache/激活那部分工作余量）还给系统，不碰被 model 强引用的权重。
        if generationTasks.isEmpty {
            let beforeMB = MLX.Memory.cacheMemory >> 20
            MLX.Memory.clearCache()
            GTLog.info("mlx idle reclaim: cache \(beforeMB)MB→\(MLX.Memory.cacheMemory >> 20)MB, " +
                       "active(权重)\(MLX.Memory.activeMemory >> 20)MB")
        }
    }

    /// repo 由 variant 推导（与 EngineHolder 的 tuningOverride 构成 variant↔repo 名不变量）
    static func repoName(for variant: ModelVariant) -> String {
        switch variant {
        case .gemma4E4B4bit: "mlx-community/gemma-4-e4b-it-4bit"
        case .gemma4E2B4bit: "mlx-community/gemma-4-e2b-it-4bit"
        }
    }

    /// 本地优先纠偏（autoTuning + macOS 默认目录路径）：autoTuning 因可用内存降了档，
    /// 但降档目标模型本地没有、而按物理内存本该选的更高档模型本地已有
    /// （新快照完整或 legacy HF 缓存任一）→ 改用更高档。
    /// 真机现场：16GB Mac 启动时 avail=3GB 被降到 E2B，本地 legacy 缓存只有 E4B(4.9GB)，
    /// 「省内存」反而触发 3.6GB 下载，且清单请求挂死时菜单永远停在「加载中」。
    /// 复用本地模型最坏是加载失败（有失败态兜底可重试），强下载最坏是长时间不可用。
    private static func preferLocalModel(over tuning: EngineTuning) -> EngineTuning {
        let byRAM = EngineTuning.recommendedByRAM(physicalMemory: SystemMemory.physical())
        guard byRAM.variant != tuning.variant,
              !hasLocalModel(for: tuning.variant),
              hasLocalModel(for: byRAM.variant) else { return tuning }
        GTLog.info("local-first override: 内存紧张但本地已有 \(byRAM.variant.rawValue)，" +
                   "优先复用避免下载 \(tuning.variant.rawValue)；内存不足风险由加载失败兜底")
        return byRAM
    }

    /// macOS 默认路径下该 variant 的模型本地是否已有：新快照完整 或 legacy HF 缓存非空
    private static func hasLocalModel(for variant: ModelVariant) -> Bool {
        let repo = repoName(for: variant)
        return ModelDownloader.isComplete(
            ModelDownloader.snapshotDirectory(in: defaultModelDirectory(), repo: repo))
            || InstalledModels.legacyCacheHasModel(
                repo: repo,
                hub: InstalledModels.defaultLegacyHuggingFaceHub
            )
    }

    /// 暴露默认模型目录给 App 层（EngineController.deleteModel / installedModels 用）
    public static func defaultModelBase() -> URL { defaultModelDirectory() }

    /// 卸载当前模型并回收工作余量缓冲（切换模型前调用）。
    /// 权重被 model 强引用；置 nil 后 ARC 释放，clearCache 再回收空闲缓冲池余量。
    public func unload() {
        model = nil
        MLX.Memory.clearCache()
        GTLog.info("mlx model unloaded (switch)")
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
        InstalledModels.legacyCacheHasModel(
            repo: repo,
            hub: InstalledModels.defaultLegacyHuggingFaceHub
        )
    }
}
