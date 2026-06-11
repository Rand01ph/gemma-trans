# MLX 迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 推理引擎 LiteRT-LM → MLX-Swift（官方 mlx-swift-lm，Gemma 4 e4b-4bit），模型应用内自动下载，退役 vendor/bootstrap/手动下载。

**Architecture:** spike 双引擎同机对比拿数据 → 通过后只重写 `TranslationEngine` 内部 + `EngineTuning` 档位语义（变体选择），协议外（HTTP/浮窗/热键/去抖）零改动 → 清理 LiteRT 全套。

**Tech Stack:** mlx-swift-lm 3.31.3（MLXLLM/MLXLMCommon）、`LLMRegistry.gemma4_e4b_it_4bit`、ChatSession.streamResponse。

**Spec:** `docs/superpowers/specs/2026-06-11-mlx-migration-design.md`

**已校准 API（源码级，/tmp/mlx-lm-check）**：`ChatSession(model, instructions: String?, generateParameters: GenerateParameters(maxTokens: Int?))`；`session.streamResponse(to: prompt) -> AsyncThrowingStream<String, Error>`。

**执行中校准（2026-06-11，实测）**：
1. 模型加载入口是 **`#huggingFaceLoadModelContainer(configuration:progressHandler:)` 宏**（MLXHuggingFace 产品）；裸 `LLMModelFactory.loadContainer` 需要显式 Downloader。消费方必须自带依赖：`swift-huggingface`（产品 HuggingFace）+ `swift-transformers`（产品 Tokenizers），并在调用文件 import 两者（宏展开引用）。
2. **SwiftPM 命令行无法编译 Metal 着色器**（mlx-swift README 明示）：`swift run`/`swift test` 下 MLX 运行时报 "Failed to load the default metallib"。CLI 与含 MLX 运行时的集成测试必须经 **xcodebuild** 构建/运行（`xcodebuild -scheme gemma-trans-cli -skipMacroValidation build`）；纯单测（不触 Metal）仍可 swift test。README 的 serve 启动命令相应改为 xcodebuild 构建产物。
3. Xcode 26 的 **Metal Toolchain 是按需组件**，首次需 `xcodebuild -downloadComponent MetalToolchain`（app/CLI 构建均依赖）。
4. xcodebuild 跑 SPM 宏需 `-skipMacroValidation`（或 Xcode GUI 信任一次）。

---

### Task 1: MLX spike（关键路径，双引擎对比）

**Files:**
- Modify: `Package.swift`（新增 mlx-swift-lm 依赖，暂不移除 LiteRT）
- Modify: `Sources/gemma-trans-cli/main.swift`（新增 `spike-mlx` 子命令）

- [ ] **Step 1: Package.swift 给 cli target 加 MLX 依赖**

dependencies 数组追加：

```swift
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
```

`gemma-trans-cli` target dependencies 追加：

```swift
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
```

- [ ] **Step 2: main.swift 加 spike-mlx**

switch 增加 case，文件底部加函数：

```swift
case "spike-mlx":
    await runSpikeMLX()
```

```swift
import MLXLLM
import MLXLMCommon

func runSpikeMLX() async {
    do {
        let clock = ContinuousClock()
        print("Loading MLX gemma-4-e4b-it-4bit (首次自动下载约 2.3GB)…")
        let loadStart = clock.now
        let model = try await LLMModelFactory.shared.loadContainer(
            configuration: LLMRegistry.gemma4_e4b_it_4bit
        ) { progress in
            print("download: \(Int(progress.fractionCompleted * 100))%", terminator: "\r")
        }
        print("\nModel ready in \(clock.now - loadStart)")

        let session = ChatSession(
            model,
            instructions: PromptBuilder.systemPrompt,
            generateParameters: GenerateParameters(maxTokens: 512)
        )
        let genStart = clock.now
        let prompt = PromptBuilder.userPrompt(
            text: "The quick brown fox jumps over the lazy dog.", target: "zh-Hans")
        var chars = 0
        for try await chunk in session.streamResponse(to: prompt) {
            print(chunk, terminator: "")
            chars += chunk.count
        }
        let elapsed = clock.now - genStart
        print("\n--- MLX spike OK: \(chars) chars in \(elapsed) ---")
    } catch {
        print("MLX SPIKE FAILED: \(error)")
        exit(1)
    }
}
```

- [ ] **Step 3: 跑 MLX spike（首次含模型下载）**

Run: `swift run gemma-trans-cli spike-mlx`
Expected: 下载进度 → 中文译文流式输出 → OK。记录加载时长、生成时长。

- [ ] **Step 4: 同机对照 LiteRT**

Run: `swift run gemma-trans-cli spike`（LiteRT 旧 spike）
对比两组数字（加载/生成）。**中止条件**：MLX 生成速度低于 LiteRT 一半或跑不通 → 停止迁移上报。

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources/gemma-trans-cli/
git commit -m "spike: MLX Gemma4 e4b-4bit 跑通，与 LiteRT 同机对比数据见 commit message"
```

（把两组实测数字写进 commit message 正文。）

### Task 2: EngineTuning 档位改为变体选择（TDD）

**Files:**
- Modify: `Sources/GemmaTransKit/EngineTuning.swift`
- Modify: `Tests/GemmaTransKitTests/EngineTuningTests.swift`

- [ ] **Step 1: 重写测试（变体语义）**

```swift
import Testing
@testable import GemmaTransKit

@Suite struct EngineTuningTests {
    let GB: UInt64 = 1 << 30
    let plenty: UInt64 = 100 << 30

    @Test func bigMachineGetsE4BLongInput() {
        let t = EngineTuning.recommended(physicalMemory: 48 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 4096, maxInputChars: 6000))
    }

    @Test func tier32GB() {
        let t = EngineTuning.recommended(physicalMemory: 32 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 3000))
    }

    @Test func tier16GB() {
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 1500))
    }

    @Test func smallMachineGetsE2B() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700))
    }

    @Test func pressureDowngradesOneTier() {
        // 16GB 物理但仅 2GB 可用 < e4b 2.4GB + 2GB 余量 → 降到 e2b 档
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: 2 * GB)
        #expect(t.variant == .gemma4E2B4bit)
    }

    @Test func pressureDowngradeStopsAtFloor() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: 1 * GB)
        #expect(t == EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700))
    }

    @Test func unknownAvailableMemoryDoesNotDowngrade() {
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: nil)
        #expect(t.variant == .gemma4E4B4bit)
    }
}
```

- [ ] **Step 2: 跑测确认失败**

Run: `swift test --filter EngineTuningTests`
Expected: FAIL（ModelVariant/新签名未定义）

- [ ] **Step 3: 实现**

```swift
import Foundation

/// MLX 模型变体（注册表 id 在引擎层映射）
public enum ModelVariant: String, Sendable {
    case gemma4E4B4bit  // ≈2.4GB
    case gemma4E2B4bit  // ≈1.5GB

    /// 估算驻留内存（权重 + 激活），用于压力降档判断
    var estimatedBytes: UInt64 {
        switch self {
        case .gemma4E4B4bit: return 2_400_000_000
        case .gemma4E2B4bit: return 1_500_000_000
        }
    }
}

/// 按机器内存推导的引擎参数。纯函数，便于全表单测。
public struct EngineTuning: Sendable, Equatable {
    public let variant: ModelVariant
    public let maxTokens: Int       // 单次生成上限
    public let maxInputChars: Int

    public init(variant: ModelVariant, maxTokens: Int, maxInputChars: Int) {
        self.variant = variant
        self.maxTokens = maxTokens
        self.maxInputChars = maxInputChars
    }

    static let tiers: [(minRAM: UInt64, tuning: EngineTuning)] = [
        (48 << 30, EngineTuning(variant: .gemma4E4B4bit, maxTokens: 4096, maxInputChars: 6000)),
        (32 << 30, EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 3000)),
        (16 << 30, EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 1500)),
        (0,        EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700)),
    ]

    /// 模型之外的工作余量（KV cache、激活、其他 app）
    static let workspaceBytes: UInt64 = 2 << 30

    public static func recommended(
        physicalMemory: UInt64, availableMemory: UInt64?
    ) -> EngineTuning {
        var index = tiers.firstIndex { physicalMemory >= $0.minRAM } ?? tiers.count - 1
        if let available = availableMemory,
           available < tiers[index].tuning.variant.estimatedBytes + workspaceBytes {
            index = min(index + 1, tiers.count - 1)
        }
        return tiers[index].tuning
    }
}
```

- [ ] **Step 4: 跑测确认通过**

Run: `swift test --filter EngineTuningTests`
Expected: PASS（7 个）。其他 target 此时编译会断（TranslationEngine 还引用旧字段）——Task 3 一起修，本任务只验证该 suite。

- [ ] **Step 5: Commit（与 Task 3 合并提交亦可，若编译断则顺延）**

### Task 3: TranslationEngine 重写 + LiteRT 退役

**Files:**
- Modify: `Sources/GemmaTransKit/TranslationEngine.swift`（整文件重写）
- Modify: `Sources/GemmaTransKit/AppSettings.swift`（删 modelPath/modelBookmark；manualMaxNumTokens 改 manualMaxTokens）
- Modify: `Package.swift`（GemmaTransKit 依赖 MLX，移除 LiteRTLM；删 LiteRT package）
- Modify: `Sources/gemma-trans-cli/main.swift`（旧 spike 删除，spike-mlx 改名 spike，serve 不变）
- Delete: `Scripts/bootstrap.sh`
- Modify: `Tests/GemmaTransKitTests/EngineIntegrationTests.swift`

- [ ] **Step 1: TranslationEngine 重写**

```swift
import Foundation
import MLXLLM
import MLXLMCommon

public actor TranslationEngine: TranslationService {
    private let settings: AppSettings
    private var model: ModelContainer?
    private var lastGeneration: Task<Void, Never>?
    private var activeGenerations = 0
    private let detector = LanguageDetector()
    private var resolvedTuning: EngineTuning?

    public var currentTuning: EngineTuning? { resolvedTuning }
    public var isGenerating: Bool { activeGenerations > 0 }

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var isReady: Bool { model != nil }

    /// 加载模型（首次自动从 HuggingFace 下载，progress 回调驱动 UI）
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
        model = try await LLMModelFactory.shared.loadContainer(configuration: configuration) { p in
            progress(p.fractionCompleted)
        }
        GTLog.info("mlx model loaded: \(configuration.name)")
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
```

（ModelContainer 跨 actor：MLXLMCommon 的 ModelContainer 自带并发安全设计（actor）；若编译报 Sendable 错，参照 Task 1 spike 的实际用法调整——spike 已验证可用形态。）

- [ ] **Step 2: AppSettings 清理**

删除 `modelPath`、`modelBookmark` 属性与持久化行、`defaultModelDirectory`；`manualMaxNumTokens` 更名 `manualMaxTokens`（UserDefaults 键同步改 "manualMaxTokens"）。init 参数列表相应精简。

- [ ] **Step 3: Package.swift 收尾 + 删 bootstrap**

- dependencies：删除 `.package(path: "Vendor/LiteRT-LM")`；mlx-swift-lm 保留
- GemmaTransKit target：依赖改 `MLXLLM`/`MLXLMCommon`（移除 LiteRTLM）
- `git rm Scripts/bootstrap.sh && rm -rf Vendor`

- [ ] **Step 4: CLI 收口**

main.swift：删除 LiteRT 的 runSpike 与 `import LiteRTLM`；`spike-mlx` 更名 `spike`；serve 分支调用 `engine.load()`（无 progress 打印则传 `{ p in print("download: \(Int(p*100))%", terminator: "\r") }`）。

- [ ] **Step 5: 集成测试适配**

```swift
import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct EngineIntegrationTests {
    /// MLX 模型经 Hub 缓存于用户目录；CI/无缓存机器自动跳过
    static var hubCachePresent: Bool {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/mlx-community")
        return FileManager.default.fileExists(atPath: base.path)
    }

    @Test(.enabled(if: hubCachePresent))
    func translatesEnglishToChinese() async throws {
        let engine = TranslationEngine(settings: AppSettings())
        try await engine.load()
        let result = try await engine.translate("Good morning", target: nil)
        #expect(result.detected == "en")
        #expect(result.target == "zh-Hans")
        let text = try await result.fullText()
        #expect(!text.isEmpty)
        print("译文: \(text)")
    }

    @Test(.enabled(if: hubCachePresent))
    func isGeneratingReflectsInflightWork() async throws {
        let engine = TranslationEngine(settings: AppSettings())
        try await engine.load()
        #expect(await engine.isGenerating == false)
        let result = try await engine.translate("Good evening", target: nil)
        #expect(await engine.isGenerating == true)
        _ = try await result.fullText()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.isGenerating == false)
    }
}
```

（Hub 实际缓存路径以 spike 下载后 `find ~ -maxdepth 4 -name "*gemma-4-e4b*" -type d 2>/dev/null` 实测为准，回写此断言。）

- [ ] **Step 6: 全量测试 + Commit**

Run: `swift test`
Expected: 全部 PASS（含 MLX 集成测试，模型已在 spike 下载）

```bash
git add -A && git commit -m "feat: 推理引擎迁移至 MLX-Swift，退役 LiteRT/vendor/手动模型下载"
```

### Task 4: App 层适配（下载进度 + 设置页）

**Files:**
- Modify: `App/GemmaTrans/EngineController.swift`
- Modify: `App/GemmaTrans/SettingsView.swift`

- [ ] **Step 1: EngineController 下载进度**

`EngineStatus` 增加 `case downloading(Int)`；start() 中：

```swift
            do {
                try await engine.load { fraction in
                    Task { @MainActor in
                        let pct = Int(fraction * 100)
                        if pct < 100 { EngineController.shared.engineStatus = .downloading(pct) }
                    }
                }
                self.engine = engine
                engineStatus = .ready
                ...
```

（`engineStatus` 需可从该闭包写：把 `private(set)` 放宽为 internal set 或加内部方法 `setDownloading(_:)`。）
MenuBarExtra 状态行增加 `case .downloading(let p): Text("引擎：模型下载中 \(p)%")`。bookmark resolve 代码块整体删除。

- [ ] **Step 2: SettingsView 模型区重写**

"模型" Section 改为：

```swift
            Section("模型") {
                LabeledContent("当前模型", value: "Gemma 4 (4-bit · 自动按内存选择 E4B/E2B)")
                Text("首次启动自动从 Hugging Face 下载（约 1.5–2.4GB）。国内网络可在启动前设置 HF_ENDPOINT 镜像。")
                    .font(.caption).foregroundStyle(.secondary)
            }
```

（NSOpenPanel/bookmark/下载链接整段删除；性能区 `manualMaxNumTokens` 改绑 `manualMaxTokens`，标签 "生成上限 (tokens)"；自动模式展示行改用 `EngineTuning.recommended(physicalMemory:availableMemory:)` 新签名。）

- [ ] **Step 3: 双 target 构建 + 真机验证**

Run: `cd App && xcodegen generate && xcodebuild -scheme GemmaTrans -configuration Debug -derivedDataPath build build && xcodebuild -scheme GemmaTrans-MAS -configuration Debug -derivedDataPath build build`（都带 `-project GemmaTrans.xcodeproj`）
Expected: 双 SUCCEEDED。
启动常规版 → menu bar 状态正常 → `/translate` 冒烟 → computer-use 文本编辑划词 ⌥D 浮窗出译文。沙盒版同样验一轮（容器内会再下载一份模型——预期行为，记录确认）。

- [ ] **Step 4: Commit**

```bash
git add App/ && git commit -m "feat: App 层 MLX 适配（下载进度状态 + 设置页模型区简化）"
```

### Task 5: 文档与发布产物（build 3）

**Files:**
- Modify: `README.md`、`docs/store-listing.md`

- [ ] **Step 1: README**：删除手动下载/bootstrap 章节（保留 `git clone` 即构建）；模型说明改自动下载 + `HF_ENDPOINT`；架构图 LiteRT → MLX。
- [ ] **Step 2: store-listing.md**：描述里 "4GB" → "约 2.4GB，应用内自动下载"；审核备注 TO TEST 段同步（无需手动放文件）。
- [ ] **Step 3: ASC 元数据同步**：`asc localizations update` 重发描述；`asc review details-update` 重发备注。
- [ ] **Step 4: 发布产物（经用户确认后执行）**：`CURRENT_PROJECT_VERSION: "3"` → MAS archive/export/upload build 3 → attach + 加密合规；`./Scripts/release.sh` 重出直分 zip（版本号 1.0.0 不变，build 3）。
- [ ] **Step 5: Commit + push**

---

## 自查

spec 覆盖：依赖替换 ✓（T1/T3）、引擎重写+串行去抖保留 ✓（T3 Step1）、档位变体化 ✓（T2）、下载进度 ✓（T4）、设置页退役路径/bookmark ✓（T3/T4）、CLI ✓（T3）、集成测试 ✓（T3）、spike 对比与中止条件 ✓（T1）、发布影响 ✓（T5）。占位扫描：Hub 缓存路径标注"实测回写"为校准点非占位；无 TBD。类型一致：`EngineTuning(variant:maxTokens:maxInputChars:)`、`recommended(physicalMemory:availableMemory:)`、`manualMaxTokens` 全文统一。
