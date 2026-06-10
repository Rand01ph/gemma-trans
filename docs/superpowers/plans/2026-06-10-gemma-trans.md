# GemmaTrans Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 本地 Gemma 4 划词翻译：menu bar app（热键划词 + 浮窗流式译文）+ 本地 HTTP API（`127.0.0.1:8765`，含 OpenAI 兼容接口，供 PopClip 等调用）。

**Architecture:** 单 Swift Package（`GemmaTransKit` 核心库 + `GemmaTransServer` HTTP 层 + `gemma-trans-cli` 验证工具），M2 再加一个 XcodeGen 生成的 SwiftUI menu bar app 引用本地包。引擎用 LiteRT-LM Swift（Metal GPU），模型 Gemma 4 E4B（`.litertlm`）。

**Tech Stack:** Swift 6（tools 6.0，macOS 14+）、LiteRT-LM（SPM `LiteRTLM`，≥0.12.0）、FlyingFox（≥0.26.0）、NaturalLanguage（语言检测）、KeyboardShortcuts（热键，M2）、XcodeGen（M2）。

**Spec:** `docs/superpowers/specs/2026-06-10-gemma-trans-design.md`

---

## 已查证的 API 事实（写代码前必读）

- **（执行中校准）LiteRT-LM 不能按远程版本引用**：其 LiteRTLM target 带 `unsafeFlags(["-Xlinker", "-all_load"])`，SPM 拒绝远程版本依赖使用 unsafe flags。解法：git submodule vendor 到 `Vendor/LiteRT-LM`（钉 v0.13.1，SHA a0afb5a），`Package.swift` 用 `.package(path: "Vendor/LiteRT-LM")`。克隆本仓库需 `git clone --recurse-submodules`。Task 11 的 XcodeGen `packages` 同样改为 `path: ../Vendor/LiteRT-LM`（如 app 直接依赖）或仅依赖本地 GemmaTransCore（已传递）。

- LiteRT-LM：`import LiteRTLM`；`EngineConfig(modelPath:backend:maxNumTokens:cacheDir:)`；`Engine(engineConfig:)`；`engine.createConversation(...)` 接受含 `systemMessage: Message(...)` 的 ConversationConfig；流式：`for try await chunk in conversation.sendMessageStream(Message("...")) { chunk.toString }`。**注意：参数名/是否 throws 以包内实际 API 为准，Task 2 spike 的目的之一就是校准这些签名；如有出入，修正后同步更新本计划后续任务中的调用代码。**
- FlyingFox（已读源码确认）：`HTTPServer(address: .loopback(port:))`；`await server.appendRoute("POST /x") { request in ... }`；请求体 `try await request.bodyData`；JSON 响应 `HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: data)`；流式响应 `HTTPResponse(statusCode:headers:body: HTTPBodySequence)`，其中 `HTTPBodySequence(from: some AsyncBufferedSequence<UInt8>, suggestedBufferSize:)`（不带 `count` → chunked 编码）。`AsyncBufferedSequence` 协议是 public，但库内置的便捷包装是 package 私有 → 需要自写适配器（Task 7）。
- 模型文件：`https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm`，文件名 `gemma-4-E4B-it.litertlm`（约 4GB）。Gemma 权重可能需要在 HF 接受许可（`hf auth login` 后下载）。
- 本机：Apple M2 / 16GB / macOS 26.5 / Swift 6.3.2 / Xcode 26.5。

## 文件结构

```
gemma-trans/
├── Package.swift
├── .gitignore
├── README.md                                  (Task 10)
├── Sources/
│   ├── GemmaTransKit/
│   │   ├── AppSettings.swift                  (Task 1)
│   │   ├── LanguageDetector.swift             (Task 3)
│   │   ├── PromptBuilder.swift                (Task 4)
│   │   ├── TranslationService.swift           (Task 5: 协议+类型)
│   │   └── TranslationEngine.swift            (Task 5: LiteRT-LM 封装)
│   ├── GemmaTransServer/
│   │   ├── APIServer.swift                    (Task 6)
│   │   ├── TranslateRoute.swift               (Task 6 非流式, Task 7 流式)
│   │   ├── SSEBody.swift                      (Task 7: AsyncBufferedSequence 适配器)
│   │   └── ChatCompletionsRoute.swift         (Task 8)
│   └── gemma-trans-cli/
│       └── main.swift                         (Task 2 spike, Task 9 serve)
├── Tests/
│   ├── GemmaTransKitTests/
│   │   ├── LanguageDetectorTests.swift        (Task 3)
│   │   ├── PromptBuilderTests.swift           (Task 4)
│   │   └── EngineIntegrationTests.swift       (Task 5, 需模型文件)
│   └── GemmaTransServerTests/
│       ├── MockTranslator.swift               (Task 6)
│       ├── TranslateRouteTests.swift          (Task 6, 7)
│       └── ChatCompletionsRouteTests.swift    (Task 8)
├── popclip/GemmaTrans.popclipext/
│   ├── Config.yaml                            (Task 10)
│   └── translate.sh                           (Task 10)
└── App/                                        (M2)
    ├── project.yml                            (Task 11)
    └── GemmaTrans/
        ├── GemmaTransApp.swift                (Task 11)
        ├── EngineController.swift             (Task 11)
        ├── SettingsView.swift                 (Task 12)
        ├── SelectionReader.swift              (Task 13)
        ├── TranslationPanel.swift             (Task 14)
        ├── HotkeyCenter.swift                 (Task 15)
        └── Info.plist                         (Task 11)
```

测试运行命令统一为：`swift test`（集成测试需 `GEMMA_MODEL_PATH` 环境变量，未设置时自动跳过）。

---

# 里程碑 M1：核心库 + HTTP API + PopClip

### Task 1: SPM 脚手架 + AppSettings

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/GemmaTransKit/AppSettings.swift`
- Test: 无（纯配置，`swift build` 即验证）

- [ ] **Step 1: 写 .gitignore**

```gitignore
.build/
.swiftpm/
DerivedData/
*.xcodeproj
.DS_Store
App/build/
*.litertlm
```

- [ ] **Step 2: 写 Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gemma-trans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GemmaTransKit", targets: ["GemmaTransKit"]),
        .library(name: "GemmaTransServer", targets: ["GemmaTransServer"]),
        .executable(name: "gemma-trans-cli", targets: ["gemma-trans-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/google-ai-edge/LiteRT-LM", from: "0.12.0"),
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.26.0"),
    ],
    targets: [
        .target(
            name: "GemmaTransKit",
            dependencies: [.product(name: "LiteRTLM", package: "LiteRT-LM")]
        ),
        .target(
            name: "GemmaTransServer",
            dependencies: ["GemmaTransKit", .product(name: "FlyingFox", package: "FlyingFox")]
        ),
        .executableTarget(
            name: "gemma-trans-cli",
            dependencies: ["GemmaTransKit", "GemmaTransServer"]
        ),
        .testTarget(name: "GemmaTransKitTests", dependencies: ["GemmaTransKit"]),
        .testTarget(name: "GemmaTransServerTests", dependencies: ["GemmaTransServer"]),
    ]
)
```

- [ ] **Step 3: 写 AppSettings**

```swift
// Sources/GemmaTransKit/AppSettings.swift
import Foundation

/// 全局配置。CLI 与 App 共用，UserDefaults 持久化（App 修改，CLI 读取）。
public struct AppSettings: Sendable {
    public var modelPath: String
    public var port: UInt16
    /// 检测为中文时的目标语言
    public var targetForChinese: String
    /// 其他语言的目标语言
    public var targetDefault: String
    public var maxInputChars: Int

    public static let defaultModelDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GemmaTrans/models", isDirectory: true)

    public static let suiteName = "com.gemmatrans.app"

    public init(
        modelPath: String = defaultModelDirectory.appendingPathComponent("gemma-4-E4B-it.litertlm").path,
        port: UInt16 = 8765,
        targetForChinese: String = "en",
        targetDefault: String = "zh-Hans",
        maxInputChars: Int = 4000
    ) {
        self.modelPath = modelPath
        self.port = port
        self.targetForChinese = targetForChinese
        self.targetDefault = targetDefault
        self.maxInputChars = maxInputChars
    }

    /// 从 UserDefaults 读取（缺省值兜底）
    public static func load() -> AppSettings {
        guard let d = UserDefaults(suiteName: suiteName) else { return AppSettings() }
        var s = AppSettings()
        if let v = d.string(forKey: "modelPath"), !v.isEmpty { s.modelPath = v }
        if d.integer(forKey: "port") > 0 { s.port = UInt16(d.integer(forKey: "port")) }
        if let v = d.string(forKey: "targetForChinese"), !v.isEmpty { s.targetForChinese = v }
        if let v = d.string(forKey: "targetDefault"), !v.isEmpty { s.targetDefault = v }
        return s
    }

    public func save() {
        guard let d = UserDefaults(suiteName: Self.suiteName) else { return }
        d.set(modelPath, forKey: "modelPath")
        d.set(Int(port), forKey: "port")
        d.set(targetForChinese, forKey: "targetForChinese")
        d.set(targetDefault, forKey: "targetDefault")
    }
}
```

- [ ] **Step 4: 验证编译**

Run: `swift build`
Expected: Build complete（首次会拉取 LiteRT-LM/FlyingFox 依赖，几分钟）。若 LiteRT-LM 解析失败（如平台不支持 SPM 直引），记录错误原文，**停止并上报**——这影响整体可行性（备选 MLX-Swift）。

- [ ] **Step 5: Commit**

```bash
git add Package.swift .gitignore Sources/
git commit -m "feat: SPM 脚手架 + AppSettings"
```

### Task 2: LiteRT-LM 可行性 spike（关键路径）

目的：证明 LiteRT-LM 在本机 macOS 上能加载 Gemma 4 E4B 并完成一次流式翻译；校准 API 签名。**此任务失败则全计划暂停，评估 MLX-Swift 备选。**

**Files:**
- Create: `Sources/gemma-trans-cli/main.swift`

- [ ] **Step 1: 下载模型（约 4GB，时间取决于带宽）**

```bash
mkdir -p ~/Library/Application\ Support/GemmaTrans/models
# 需要 hf CLI：brew install huggingface-cli（或 pipx install huggingface_hub[cli]）
# Gemma 权重需接受许可：未登录则先 hf auth login
hf download litert-community/gemma-4-E4B-it-litert-lm gemma-4-E4B-it.litertlm \
  --local-dir ~/Library/Application\ Support/GemmaTrans/models
ls -lh ~/Library/Application\ Support/GemmaTrans/models/
```

Expected: `gemma-4-E4B-it.litertlm` 约 4GB。若 401/403 → 浏览器打开 HF 模型页接受 Gemma 许可后重试。

- [ ] **Step 2: 写 spike main.swift**

```swift
// Sources/gemma-trans-cli/main.swift
import Foundation
import LiteRTLM

// Spike：加载引擎 → 翻译一句话 → 流式打印。API 签名若与此处不符，以包内为准修正。
let settings = AppSettingsCLI.resolve()

func runSpike() async {
    do {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaTrans").path
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        print("Loading model: \(settings.modelPath)")
        let config = try EngineConfig(
            modelPath: settings.modelPath,
            backend: .gpu,
            maxNumTokens: 4096,
            cacheDir: cacheDir
        )
        let engine = try Engine(engineConfig: config)
        let conversation = try await engine.createConversation()
        print("Model ready. Translating…")
        let prompt = "Translate the following text into Simplified Chinese. Output only the translation.\n\nThe quick brown fox jumps over the lazy dog."
        for try await chunk in conversation.sendMessageStream(Message(prompt)) {
            print(chunk.toString, terminator: "")
        }
        print("\n--- spike OK ---")
    } catch {
        print("SPIKE FAILED: \(error)")
        exit(1)
    }
}

enum AppSettingsCLI {
    static func resolve() -> (modelPath: String, port: UInt16) {
        let env = ProcessInfo.processInfo.environment
        let defaults = GemmaTransKit.AppSettings.load()
        return (env["GEMMA_MODEL_PATH"] ?? defaults.modelPath, defaults.port)
    }
}

import GemmaTransKit
await runSpike()
```

注：顶层 `await` 在 executableTarget 的 main.swift 中可用。`import` 放文件中部不规范，整理为文件顶部统一 `import Foundation / LiteRTLM / GemmaTransKit`。

- [ ] **Step 3: 编译并修正 API 签名**

Run: `swift build 2>&1 | head -50`
Expected: 若 `EngineConfig`/`Engine`/`createConversation`/`sendMessageStream`/`Message` 任一签名不符 → 用 `swift package describe` / 查看 `.build/checkouts/LiteRT-LM` 内 Swift 接口文件，修正调用；**并把修正后的真实签名同步进本计划 Task 5 的代码**。

- [ ] **Step 4: 运行 spike**

Run: `swift run gemma-trans-cli`
Expected: 打印中文译文（"敏捷的棕色狐狸…"之类）+ `--- spike OK ---`。记录加载耗时与生成速度（肉眼）。失败 → 停止上报。

- [ ] **Step 5: Commit**

```bash
git add Sources/gemma-trans-cli/
git commit -m "feat: LiteRT-LM spike 通过——Gemma 4 E4B 本机可用"
```

### Task 3: LanguageDetector（TDD）

**Files:**
- Create: `Sources/GemmaTransKit/LanguageDetector.swift`
- Test: `Tests/GemmaTransKitTests/LanguageDetectorTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Tests/GemmaTransKitTests/LanguageDetectorTests.swift
import Testing
@testable import GemmaTransKit

@Suite struct LanguageDetectorTests {
    let settings = AppSettings()  // targetForChinese=en, targetDefault=zh-Hans
    let detector = LanguageDetector()

    @Test func englishGoesToChinese() {
        let r = detector.plan(for: "The quick brown fox jumps over the lazy dog.", settings: settings)
        #expect(r.detected == "en")
        #expect(r.target == "zh-Hans")
    }

    @Test func chineseGoesToEnglish() {
        let r = detector.plan(for: "今天天气真不错，我们去公园散步吧。", settings: settings)
        #expect(r.detected.hasPrefix("zh"))
        #expect(r.target == "en")
    }

    @Test func japaneseGoesToChinese() {
        let r = detector.plan(for: "今日はいい天気ですね。公園へ散歩に行きましょう。", settings: settings)
        #expect(r.detected == "ja")
        #expect(r.target == "zh-Hans")
    }

    @Test func explicitTargetWins() {
        let r = detector.plan(for: "Hello world, nice to meet you.", target: "fr", settings: settings)
        #expect(r.target == "fr")
    }

    @Test func emptyTextFallsBackToDefault() {
        let r = detector.plan(for: "", settings: settings)
        #expect(r.detected == "und")
        #expect(r.target == "zh-Hans")
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LanguageDetectorTests`
Expected: FAIL（LanguageDetector 未定义）

- [ ] **Step 3: 实现**

```swift
// Sources/GemmaTransKit/LanguageDetector.swift
import Foundation
import NaturalLanguage

public struct LanguagePlan: Sendable, Equatable {
    public let detected: String  // BCP-47，无法识别为 "und"
    public let target: String
}

public struct LanguageDetector: Sendable {
    public init() {}

    /// target 显式给定时优先；否则中文→targetForChinese，其余→targetDefault
    public func plan(for text: String, target: String? = nil, settings: AppSettings) -> LanguagePlan {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage?.rawValue ?? "und"
        if let target { return LanguagePlan(detected: detected, target: target) }
        let isChinese = detected.hasPrefix("zh")
        return LanguagePlan(
            detected: detected,
            target: isChinese ? settings.targetForChinese : settings.targetDefault
        )
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LanguageDetectorTests`
Expected: PASS（5 个测试）。注意：`NLLanguageRecognizer` 对短文本可能误判，测试用例都用整句；若 `ja` 用例失败，检查实际返回值，必要时换更长的日文句子，不要放宽断言。

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/LanguageDetector.swift Tests/
git commit -m "feat: 语言检测（NaturalLanguage，智能双向）"
```

### Task 4: PromptBuilder（TDD）

**Files:**
- Create: `Sources/GemmaTransKit/PromptBuilder.swift`
- Test: `Tests/GemmaTransKitTests/PromptBuilderTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Tests/GemmaTransKitTests/PromptBuilderTests.swift
import Testing
@testable import GemmaTransKit

@Suite struct PromptBuilderTests {
    @Test func promptContainsTextAndTargetName() {
        let p = PromptBuilder.userPrompt(text: "Hello world", target: "zh-Hans")
        #expect(p.contains("Hello world"))
        #expect(p.contains("Simplified Chinese"))
    }

    @Test func systemPromptForbidsExplanation() {
        let s = PromptBuilder.systemPrompt
        #expect(s.contains("only"))
    }

    @Test func unknownBCP47FallsBackToRawCode() {
        let p = PromptBuilder.userPrompt(text: "Hi", target: "xx-weird")
        #expect(p.contains("xx-weird"))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter PromptBuilderTests`
Expected: FAIL（PromptBuilder 未定义）

- [ ] **Step 3: 实现**

```swift
// Sources/GemmaTransKit/PromptBuilder.swift
import Foundation

public enum PromptBuilder {
    public static let systemPrompt = """
    You are a professional translation engine. Output only the translation of the user's text. \
    Do not explain, do not add quotes, do not answer questions in the text. \
    Preserve line breaks and formatting.
    """

    static let languageNames: [String: String] = [
        "zh-Hans": "Simplified Chinese",
        "zh-Hant": "Traditional Chinese",
        "zh": "Simplified Chinese",
        "en": "English",
        "ja": "Japanese",
        "ko": "Korean",
        "fr": "French",
        "de": "German",
        "es": "Spanish",
        "ru": "Russian",
    ]

    public static func userPrompt(text: String, target: String) -> String {
        let name = languageNames[target] ?? target
        return "Translate the following text into \(name). Output only the translation.\n\n\(text)"
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter PromptBuilderTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/PromptBuilder.swift Tests/
git commit -m "feat: 翻译提示词模板"
```

### Task 5: TranslationService 协议 + TranslationEngine

**Files:**
- Create: `Sources/GemmaTransKit/TranslationService.swift`
- Create: `Sources/GemmaTransKit/TranslationEngine.swift`
- Test: `Tests/GemmaTransKitTests/EngineIntegrationTests.swift`（需模型，无模型自动跳过）

- [ ] **Step 1: 定义协议与类型**

```swift
// Sources/GemmaTransKit/TranslationService.swift
import Foundation

public struct TranslationStreamResult: Sendable {
    public let detected: String
    public let target: String
    public let truncated: Bool
    public let chunks: AsyncThrowingStream<String, Error>

    public init(detected: String, target: String, truncated: Bool, chunks: AsyncThrowingStream<String, Error>) {
        self.detected = detected
        self.target = target
        self.truncated = truncated
        self.chunks = chunks
    }

    /// 聚合为完整译文（非流式调用方用）
    public func fullText() async throws -> String {
        var out = ""
        for try await c in chunks { out += c }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol TranslationService: Sendable {
    /// target 为 nil 时按智能双向规则自动决定
    func translate(_ text: String, target: String?) async throws -> TranslationStreamResult
    var isReady: Bool { get async }
}

public enum TranslationError: Error, Sendable {
    case modelNotLoaded
    case emptyInput
    case queueTimeout
}
```

- [ ] **Step 2: 实现 TranslationEngine（actor，串行排队，一次性 conversation）**

注意：以下 LiteRT-LM 调用以 Task 2 spike 校准后的真实签名为准。

```swift
// Sources/GemmaTransKit/TranslationEngine.swift
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
    public func load() throws {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaTrans").path
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let config = try EngineConfig(
            modelPath: settings.modelPath,
            backend: .gpu,
            maxNumTokens: 4096,
            cacheDir: cacheDir
        )
        engine = try Engine(engineConfig: config)
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
            do {
                let conversation = try await engine.createConversation()
                for try await chunk in conversation.sendMessageStream(Message(prompt)) {
                    continuation.yield(chunk.toString)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return TranslationStreamResult(
            detected: plan.detected, target: plan.target, truncated: truncated, chunks: stream
        )
    }
}
```

系统指令：spike 校准 `createConversation` 是否接受 `ConversationConfig(systemMessage: Message(PromptBuilder.systemPrompt))`；若支持则传入并从 userPrompt 中去掉重复指令（保留 "Translate into X" 行）；若不支持则维持单条 prompt（现状已可工作）。

- [ ] **Step 3: 集成测试（无模型自动跳过）**

```swift
// Tests/GemmaTransKitTests/EngineIntegrationTests.swift
import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct EngineIntegrationTests {
    static var modelPath: String? {
        let env = ProcessInfo.processInfo.environment["GEMMA_MODEL_PATH"]
        let fallback = AppSettings().modelPath
        if let env, FileManager.default.fileExists(atPath: env) { return env }
        if FileManager.default.fileExists(atPath: fallback) { return fallback }
        return nil
    }

    @Test(.enabled(if: modelPath != nil))
    func translatesEnglishToChinese() async throws {
        var settings = AppSettings()
        settings.modelPath = Self.modelPath!
        let engine = TranslationEngine(settings: settings)
        try await engine.load()
        let result = try await engine.translate("Good morning", target: nil)
        #expect(result.detected == "en")
        #expect(result.target == "zh-Hans")
        let text = try await result.fullText()
        #expect(!text.isEmpty)
        print("译文: \(text)")
    }
}
```

- [ ] **Step 4: 运行测试**

Run: `swift test --filter EngineIntegrationTests`
Expected: PASS（模型已在 Task 2 下载，约 30-60s 含加载）。同时 `swift test` 全量跑一遍确认其他测试未破坏。

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/ Tests/
git commit -m "feat: TranslationService 协议 + LiteRT-LM 引擎封装（串行排队/截断/智能双向）"
```

### Task 6: HTTP Server——/health + /translate 非流式（TDD）

**Files:**
- Create: `Sources/GemmaTransServer/APIServer.swift`
- Create: `Sources/GemmaTransServer/TranslateRoute.swift`
- Test: `Tests/GemmaTransServerTests/MockTranslator.swift`
- Test: `Tests/GemmaTransServerTests/TranslateRouteTests.swift`

- [ ] **Step 1: 写 MockTranslator**

```swift
// Tests/GemmaTransServerTests/MockTranslator.swift
import Foundation
import GemmaTransKit

struct MockTranslator: TranslationService {
    var ready = true
    var chunks: [String] = ["你好", "，", "世界"]
    var detected = "en"
    var target = "zh-Hans"

    var isReady: Bool { get async { ready } }

    func translate(_ text: String, target: String?) async throws -> TranslationStreamResult {
        guard !text.isEmpty else { throw TranslationError.emptyInput }
        guard ready else { throw TranslationError.modelNotLoaded }
        let (stream, cont) = AsyncThrowingStream.makeStream(of: String.self)
        let pieces = chunks
        Task {
            for p in pieces { cont.yield(p) }
            cont.finish()
        }
        return TranslationStreamResult(
            detected: detected, target: target ?? self.target, truncated: false, chunks: stream
        )
    }
}
```

- [ ] **Step 2: 写失败测试（启动真实 server 于随机端口，URLSession 调用）**

```swift
// Tests/GemmaTransServerTests/TranslateRouteTests.swift
import Testing
import Foundation
import FlyingFox
@testable import GemmaTransServer
import GemmaTransKit

@Suite struct TranslateRouteTests {
    func startServer(_ translator: some TranslationService) async throws -> (URL, Task<Void, Error>) {
        let api = APIServer(translator: translator, port: 0)
        let task = Task { try await api.run() }
        let port = try await api.waitForPort()
        return (URL(string: "http://127.0.0.1:\(port)")!, task)
    }

    @Test func healthReturnsReady() async throws {
        let (base, task) = try await startServer(MockTranslator())
        defer { task.cancel() }
        let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("health"))
        #expect((resp as! HTTPURLResponse).statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["status"] as? String == "ready")
    }

    @Test func translateReturnsTranslation() async throws {
        let (base, task) = try await startServer(MockTranslator())
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "Hello, world"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as! HTTPURLResponse).statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["translation"] as? String == "你好，世界")
        #expect(json["detected"] as? String == "en")
        #expect(json["target"] as? String == "zh-Hans")
    }

    @Test func emptyTextReturns400() async throws {
        let (base, task) = try await startServer(MockTranslator())
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": ""])
        let (_, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as! HTTPURLResponse).statusCode == 400)
    }

    @Test func engineNotReadyReturns503() async throws {
        let (base, task) = try await startServer(MockTranslator(ready: false))
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "hi"])
        let (_, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as! HTTPURLResponse).statusCode == 503)
    }
}
```

- [ ] **Step 3: 运行确认失败**

Run: `swift test --filter TranslateRouteTests`
Expected: FAIL（APIServer 未定义）

- [ ] **Step 4: 实现 APIServer + TranslateRoute（非流式）**

```swift
// Sources/GemmaTransServer/APIServer.swift
import Foundation
import FlyingFox
import GemmaTransKit

public struct APIServer: Sendable {
    let translator: any TranslationService
    let server: HTTPServer

    public init(translator: any TranslationService, port: UInt16) {
        self.translator = translator
        self.server = HTTPServer(address: .loopback(port: port))
    }

    public func run() async throws {
        await registerRoutes()
        try await server.run()
    }

    /// 等待监听就绪并返回实际端口（port 0 时由系统分配，测试用）
    public func waitForPort() async throws -> UInt16 {
        try await server.waitUntilListening()
        guard let addr = await server.listeningAddress, case let .ip4(_, port) = addr else {
            throw URLError(.cannotConnectToHost)
        }
        return port
    }

    func registerRoutes() async {
        let t = translator
        await server.appendRoute("GET /health") { _ in
            let ready = await t.isReady
            return try .json(["status": ready ? "ready" : "loading"], statusCode: ready ? .ok : .serviceUnavailable)
        }
        await registerTranslateRoute(server: server, translator: t)
        // Task 8 在此追加 chat/completions 路由
    }
}

extension HTTPResponse {
    static func json(_ object: Any, statusCode: HTTPStatusCode = .ok) throws -> HTTPResponse {
        let data = try JSONSerialization.data(withJSONObject: object)
        return HTTPResponse(statusCode: statusCode, headers: [.contentType: "application/json"], body: data)
    }
}
```

```swift
// Sources/GemmaTransServer/TranslateRoute.swift
import Foundation
import FlyingFox
import GemmaTransKit

struct TranslateRequest: Decodable {
    let text: String
    let target: String?
    let stream: Bool?
}

/// 排队/首 token 超时（spec：30 秒未开始产出 → 503）。测试注入小值。
func withFirstChunkTimeout<T: Sendable>(
    _ seconds: Double, _ op: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TranslationError.queueTimeout
        }
        guard let first = try await group.next() else { throw TranslationError.queueTimeout }
        group.cancelAll()
        return first
    }
}

func registerTranslateRoute(
    server: HTTPServer, translator: any TranslationService, queueTimeout: Double = 30
) async {
    await server.appendRoute("POST /translate") { request in
        let body = try await request.bodyData
        guard let req = try? JSONDecoder().decode(TranslateRequest.self, from: body) else {
            return try .json(["error": "invalid JSON, expect {\"text\": ...}"], statusCode: .badRequest)
        }
        do {
            let result = try await translator.translate(req.text, target: req.target)
            // 流式分支 Task 7 实现；本任务先全部走非流式
            let text = try await withFirstChunkTimeout(queueTimeout) { try await result.fullText() }
            return try .json([
                "translation": text,
                "detected": result.detected,
                "target": result.target,
                "truncated": result.truncated,
            ])
        } catch TranslationError.emptyInput {
            return try .json(["error": "text is empty"], statusCode: .badRequest)
        } catch TranslationError.modelNotLoaded {
            return try .json(["error": "model not loaded"], statusCode: .serviceUnavailable)
        } catch TranslationError.queueTimeout {
            return try .json(["error": "engine busy, timed out"], statusCode: .serviceUnavailable)
        }
    }
}
```

`APIServer` 中 `registerTranslateRoute(server: server, translator: t)` 改为透传可配超时：`APIServer.init` 增加 `queueTimeout: Double = 30` 存储属性并传入。超时测试（追加到 TranslateRouteTests，用 0.2 秒超时 + 永不产出的 mock）：

```swift
struct StuckTranslator: TranslationService {
    var isReady: Bool { get async { true } }
    func translate(_ text: String, target: String?) async throws -> TranslationStreamResult {
        let (stream, _) = AsyncThrowingStream.makeStream(of: String.self)  // 永不 yield 也不 finish
        return TranslationStreamResult(detected: "en", target: "zh-Hans", truncated: false, chunks: stream)
    }
}

@Test func busyEngineTimesOutWith503() async throws {
    let api = APIServer(translator: StuckTranslator(), port: 0, queueTimeout: 0.2)
    let task = Task { try await api.run() }
    defer { task.cancel() }
    let port = try await api.waitForPort()
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/translate")!)
    req.httpMethod = "POST"
    req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "hi"])
    let (_, resp) = try await URLSession.shared.data(for: req)
    #expect((resp as! HTTPURLResponse).statusCode == 503)
}
```

注：`server.listeningAddress` 的 case 形态（`.ip4(String, port: UInt16)`）以 FlyingFox 实际枚举为准，编译报错时对照 `.build/checkouts/FlyingFox` 修正。

- [ ] **Step 5: 运行确认通过**

Run: `swift test --filter TranslateRouteTests`
Expected: PASS（4 个测试）

- [ ] **Step 6: Commit**

```bash
git add Sources/GemmaTransServer/ Tests/
git commit -m "feat: HTTP API——/health + /translate 非流式（mock 注入测试）"
```

### Task 7: SSE 流式 /translate

**Files:**
- Create: `Sources/GemmaTransServer/SSEBody.swift`
- Modify: `Sources/GemmaTransServer/TranslateRoute.swift`
- Test: `Tests/GemmaTransServerTests/TranslateRouteTests.swift`（追加）

- [ ] **Step 1: 追加失败测试**

```swift
// 追加到 TranslateRouteTests.swift
@Test func streamTranslateSendsSSE() async throws {
    let (base, task) = try await startServer(MockTranslator())
    defer { task.cancel() }
    var req = URLRequest(url: base.appendingPathComponent("translate"))
    req.httpMethod = "POST"
    req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "Hello", "stream": true])
    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
    let http = resp as! HTTPURLResponse
    #expect(http.statusCode == 200)
    #expect(http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true)
    var events: [String] = []
    for try await line in bytes.lines where line.hasPrefix("data: ") {
        events.append(String(line.dropFirst(6)))
        if events.last == "[DONE]" { break }
    }
    #expect(events.count == 5)  // 3 个 delta + 1 个 final + [DONE]
    #expect(events[0].contains("你好"))
    #expect(events[3].contains("\"translation\""))
    #expect(events.last == "[DONE]")
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter streamTranslateSendsSSE`
Expected: FAIL（当前 stream:true 仍走非流式 JSON，Content-Type 断言失败）

- [ ] **Step 3: 实现 SSEBody 适配器**

```swift
// Sources/GemmaTransServer/SSEBody.swift
import Foundation
import FlyingFox

/// 把 AsyncStream<Data> 适配成 FlyingFox 需要的 AsyncBufferedSequence<UInt8>，
/// 配合 HTTPBodySequence(from:) 实现 chunked/SSE 输出。
struct SSEBody: AsyncBufferedSequence, Sendable {
    typealias Element = UInt8
    let stream: AsyncStream<Data>

    func makeAsyncIterator() -> Iterator { Iterator(inner: stream.makeAsyncIterator()) }

    struct Iterator: AsyncBufferedIteratorProtocol {
        var inner: AsyncStream<Data>.AsyncIterator
        var pending: ArraySlice<UInt8> = []

        mutating func next() async -> UInt8? {
            if pending.isEmpty {
                guard let data = await inner.next() else { return nil }
                pending = ArraySlice(data)
            }
            return pending.popFirst()
        }

        mutating func nextBuffer(suggested count: Int) async -> ArraySlice<UInt8>? {
            if !pending.isEmpty {
                defer { pending = [] }
                return pending
            }
            guard let data = await inner.next() else { return nil }
            return ArraySlice(data)
        }
    }
}

enum SSE {
    static func event(_ json: Any) -> Data {
        let payload = (try? JSONSerialization.data(withJSONObject: json)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Data("data: \(payload)\n\n".utf8)
    }
    static let done = Data("data: [DONE]\n\n".utf8)
    static let headers: HTTPHeaders = [
        .contentType: "text/event-stream",
        HTTPHeader("Cache-Control"): "no-cache",
    ]
}
```

- [ ] **Step 4: TranslateRoute 加流式分支**

在 `registerTranslateRoute` 的 `do` 块内、`fullText()` 之前插入：

```swift
if req.stream == true {
    let meta = (detected: result.detected, target: result.target, truncated: result.truncated)
    let (dataStream, cont) = AsyncStream.makeStream(of: Data.self)
    Task {
        var full = ""
        do {
            for try await chunk in result.chunks {
                full += chunk
                cont.yield(SSE.event(["delta": chunk]))
            }
            cont.yield(SSE.event([
                "translation": full.trimmingCharacters(in: .whitespacesAndNewlines),
                "detected": meta.detected, "target": meta.target, "truncated": meta.truncated,
            ]))
        } catch {
            cont.yield(SSE.event(["error": "\(error)"]))
        }
        cont.yield(SSE.done)
        cont.finish()
    }
    return HTTPResponse(
        statusCode: .ok, headers: SSE.headers,
        body: HTTPBodySequence(from: SSEBody(stream: dataStream), suggestedBufferSize: 1024)
    )
}
```

- [ ] **Step 5: 运行确认通过 + 全量回归**

Run: `swift test --filter TranslateRouteTests && swift test`
Expected: 全部 PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/GemmaTransServer/ Tests/
git commit -m "feat: /translate SSE 流式输出"
```

### Task 8: OpenAI 兼容 /v1/chat/completions

**Files:**
- Create: `Sources/GemmaTransServer/ChatCompletionsRoute.swift`
- Modify: `Sources/GemmaTransServer/APIServer.swift`（registerRoutes 追加一行）
- Test: `Tests/GemmaTransServerTests/ChatCompletionsRouteTests.swift`

设计：把最后一条 user 消息全文交给引擎按"智能双向"翻译（忽略客户端的 system 消息与 model 字段——本服务是翻译器，不是通用聊天）。这让 PopClip/Bob 等"OpenAI 接口"工具配上就是翻译。

- [ ] **Step 1: 写失败测试**

```swift
// Tests/GemmaTransServerTests/ChatCompletionsRouteTests.swift
import Testing
import Foundation
import FlyingFox
@testable import GemmaTransServer
import GemmaTransKit

@Suite struct ChatCompletionsRouteTests {
    func startServer() async throws -> (URL, Task<Void, Error>) {
        let api = APIServer(translator: MockTranslator(), port: 0)
        let task = Task { try await api.run() }
        let port = try await api.waitForPort()
        return (URL(string: "http://127.0.0.1:\(port)")!, task)
    }

    func post(_ base: URL, _ body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, resp as! HTTPURLResponse)
    }

    @Test func nonStreamCompletion() async throws {
        let (base, task) = try await startServer()
        defer { task.cancel() }
        let (data, resp) = try await post(base, [
            "model": "whatever",
            "messages": [["role": "user", "content": "Hello, world"]],
        ])
        #expect(resp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choices = json["choices"] as! [[String: Any]]
        let message = choices[0]["message"] as! [String: Any]
        #expect(message["content"] as? String == "你好，世界")
        #expect(json["object"] as? String == "chat.completion")
    }

    @Test func streamCompletionSendsDeltas() async throws {
        let (base, task) = try await startServer()
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": "Hello"]], "stream": true,
        ])
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        #expect((resp as! HTTPURLResponse).value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true)
        var deltas: [String] = []
        var sawDone = false
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { sawDone = true; break }
            let json = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: Any]
            #expect(json["object"] as? String == "chat.completion.chunk")
            let delta = ((json["choices"] as! [[String: Any]])[0]["delta"] as! [String: Any])
            if let c = delta["content"] as? String { deltas.append(c) }
        }
        #expect(deltas.joined() == "你好，世界")
        #expect(sawDone)
    }

    @Test func noUserMessageReturns400() async throws {
        let (base, task) = try await startServer()
        defer { task.cancel() }
        let (_, resp) = try await post(base, ["messages": []])
        #expect(resp.statusCode == 400)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter ChatCompletionsRouteTests`
Expected: FAIL（404，路由不存在）

- [ ] **Step 3: 实现路由**

```swift
// Sources/GemmaTransServer/ChatCompletionsRoute.swift
import Foundation
import FlyingFox
import GemmaTransKit

struct ChatMessage: Decodable { let role: String; let content: String }
struct ChatRequest: Decodable {
    let messages: [ChatMessage]
    let stream: Bool?
}

func registerChatCompletionsRoute(server: HTTPServer, translator: any TranslationService) async {
    await server.appendRoute("POST /v1/chat/completions") { request in
        let body = try await request.bodyData
        guard let req = try? JSONDecoder().decode(ChatRequest.self, from: body),
              let userText = req.messages.last(where: { $0.role == "user" })?.content,
              !userText.isEmpty else {
            return try .json(["error": ["message": "no user message"]], statusCode: .badRequest)
        }
        do {
            let result = try await translator.translate(userText, target: nil)
            if req.stream == true {
                let (dataStream, cont) = AsyncStream.makeStream(of: Data.self)
                Task {
                    do {
                        for try await chunk in result.chunks {
                            cont.yield(SSE.event(chatChunk(content: chunk, finish: nil)))
                        }
                        cont.yield(SSE.event(chatChunk(content: nil, finish: "stop")))
                    } catch {
                        cont.yield(SSE.event(chatChunk(content: nil, finish: "stop")))
                    }
                    cont.yield(SSE.done)
                    cont.finish()
                }
                return HTTPResponse(
                    statusCode: .ok, headers: SSE.headers,
                    body: HTTPBodySequence(from: SSEBody(stream: dataStream), suggestedBufferSize: 1024)
                )
            }
            let text = try await result.fullText()
            return try .json([
                "id": "chatcmpl-gemmatrans",
                "object": "chat.completion",
                "model": "gemma-4-e4b-local",
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": text],
                    "finish_reason": "stop",
                ]],
                "usage": ["prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0],
            ])
        } catch TranslationError.modelNotLoaded {
            return try .json(["error": ["message": "model not loaded"]], statusCode: .serviceUnavailable)
        }
    }
}

private func chatChunk(content: String?, finish: String?) -> [String: Any] {
    var delta: [String: Any] = [:]
    if let content { delta["content"] = content }
    return [
        "id": "chatcmpl-gemmatrans",
        "object": "chat.completion.chunk",
        "model": "gemma-4-e4b-local",
        "choices": [["index": 0, "delta": delta, "finish_reason": finish as Any]],
    ]
}
```

`APIServer.registerRoutes()` 追加：

```swift
await registerChatCompletionsRoute(server: server, translator: t)
```

- [ ] **Step 4: 运行确认通过 + 全量回归**

Run: `swift test`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransServer/ Tests/
git commit -m "feat: OpenAI 兼容 /v1/chat/completions（含流式）"
```

### Task 9: CLI serve 命令 + 真机冒烟

**Files:**
- Modify: `Sources/gemma-trans-cli/main.swift`（spike 改为子命令）

- [ ] **Step 1: 改写 main.swift 支持 `spike` / `serve`**

```swift
// Sources/gemma-trans-cli/main.swift
import Foundation
import GemmaTransKit
import GemmaTransServer
import LiteRTLM

let settings: AppSettings = {
    var s = AppSettings.load()
    if let p = ProcessInfo.processInfo.environment["GEMMA_MODEL_PATH"] { s.modelPath = p }
    return s
}()

let mode = CommandLine.arguments.dropFirst().first ?? "serve"

switch mode {
case "spike":
    // 保留 Task 2 的 runSpike() 内容（签名已校准）
    await runSpike(settings: settings)
case "serve":
    let engine = TranslationEngine(settings: settings)
    print("Loading model: \(settings.modelPath)")
    do { try await engine.load() } catch {
        print("模型加载失败: \(error)\n请确认模型文件存在，下载命令见 README。")
        exit(1)
    }
    print("Model ready. Listening on http://127.0.0.1:\(settings.port)")
    let api = APIServer(translator: engine, port: settings.port)
    try await api.run()
default:
    print("usage: gemma-trans-cli [spike|serve]")
    exit(2)
}
```

（`runSpike` 抽成函数移到同文件底部，内容同 Task 2。）

- [ ] **Step 2: 编译 + 启动**

Run: `swift build && swift run gemma-trans-cli serve &`（后台），等待打印 `Model ready`
Expected: 监听 8765

- [ ] **Step 3: 真机冒烟（M1 验收第一项）**

```bash
curl -s http://127.0.0.1:8765/health
curl -s -X POST http://127.0.0.1:8765/translate -H 'Content-Type: application/json' \
  -d '{"text": "The quick brown fox jumps over the lazy dog."}'
curl -s -N -X POST http://127.0.0.1:8765/translate -H 'Content-Type: application/json' \
  -d '{"text": "今天天气真好", "stream": true}'
curl -s -X POST http://127.0.0.1:8765/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "Hello world"}]}'
```

Expected: health=ready；中文译文 JSON；SSE 逐 delta 输出英文译文；OpenAI 格式响应。完成后 kill 后台进程。

- [ ] **Step 4: Commit**

```bash
git add Sources/gemma-trans-cli/
git commit -m "feat: CLI serve 命令，真机冒烟通过"
```

### Task 10: PopClip 扩展 + README（M1 收尾）

**Files:**
- Create: `popclip/GemmaTrans.popclipext/Config.yaml`
- Create: `popclip/GemmaTrans.popclipext/translate.sh`
- Create: `README.md`

- [ ] **Step 1: 写 PopClip 扩展**

```yaml
# popclip/GemmaTrans.popclipext/Config.yaml
name: GemmaTrans
icon: symbol:character.bubble
after: show-result
shell script file: translate.sh
```

```sh
#!/bin/zsh
# popclip/GemmaTrans.popclipext/translate.sh
python3 - <<'EOF'
import json, os, urllib.request
try:
    req = urllib.request.Request(
        "http://127.0.0.1:8765/translate",
        data=json.dumps({"text": os.environ.get("POPCLIP_TEXT", "")}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        print(json.load(r)["translation"], end="")
except Exception as e:
    print(f"GemmaTrans 未运行? {e}", end="")
EOF
```

```bash
chmod +x popclip/GemmaTrans.popclipext/translate.sh
```

- [ ] **Step 2: 写 README**

内容必须包含（用实际验证过的命令）：项目简介；模型下载命令（Task 2 Step 1 原文）；`swift run gemma-trans-cli serve` 启动；三个 curl 示例（Task 9 原文）；PopClip 安装（双击 `popclip/GemmaTrans.popclipext` 目录即安装，PopClip 会提示）；API 文档表（/health、/translate 请求响应字段、/v1/chat/completions 兼容说明）；M2 预告一句。

- [ ] **Step 3: 手动验收 PopClip（M1 验收第二项）**

Run: `swift run gemma-trans-cli serve` 保持运行 → 双击安装扩展 → 任意 app 选中英文句子 → 点 PopClip 的 GemmaTrans 图标
Expected: PopClip 顶部显示中文译文。若 Config.yaml 键名报错，对照 PopClip 文档（https://www.popclip.app/dev/）修正键名后重装。

- [ ] **Step 4: Commit（M1 完成）**

```bash
git add popclip/ README.md
git commit -m "feat: PopClip 扩展 + README——M1 验收通过"
```

---

# 里程碑 M2：menu bar app + 热键划词 + 浮窗

### Task 11: App 脚手架（XcodeGen + MenuBarExtra + 引擎/服务启动）

**Files:**
- Create: `App/project.yml`
- Create: `App/GemmaTrans/GemmaTransApp.swift`
- Create: `App/GemmaTrans/EngineController.swift`
- Create: `App/GemmaTrans/Info.plist`

- [ ] **Step 1: 安装 XcodeGen 并写 project.yml**

```bash
which xcodegen || brew install xcodegen
```

```yaml
# App/project.yml
name: GemmaTrans
options:
  bundleIdPrefix: com.gemmatrans
  deploymentTarget:
    macOS: "14.0"
packages:
  GemmaTransCore:
    path: ../
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 2.0.0
targets:
  GemmaTrans:
    type: application
    platform: macOS
    sources: [GemmaTrans]
    info:
      path: GemmaTrans/Info.plist
      properties:
        LSUIElement: true            # menu bar app，不出现在 Dock
        NSHumanReadableCopyright: ""
    dependencies:
      - package: GemmaTransCore
        product: GemmaTransKit
      - package: GemmaTransCore
        product: GemmaTransServer
      - package: KeyboardShortcuts
    settings:
      base:
        ENABLE_APP_SANDBOX: NO
        CODE_SIGN_IDENTITY: "-"      # ad-hoc 签名，本机使用
```

- [ ] **Step 2: 写 EngineController（状态机 + 启动加载）**

```swift
// App/GemmaTrans/EngineController.swift
import Foundation
import GemmaTransKit
import GemmaTransServer

@MainActor @Observable
final class EngineController {
    enum Status: Equatable { case loading, ready, failed(String) }
    private(set) var status: Status = .loading
    private(set) var engine: TranslationEngine?
    private var serverTask: Task<Void, Error>?
    let settings = AppSettings.load()

    func start() {
        status = .loading
        Task {
            let engine = TranslationEngine(settings: settings)
            do {
                try await engine.load()
                self.engine = engine
                self.serverTask = Task.detached {
                    try await APIServer(translator: engine, port: self.settings.port).run()
                }
                self.status = .ready
            } catch {
                self.status = .failed("\(error)")
            }
        }
    }
}
```

- [ ] **Step 3: 写 GemmaTransApp（MenuBarExtra）**

```swift
// App/GemmaTrans/GemmaTransApp.swift
import SwiftUI

@main
struct GemmaTransApp: App {
    @State private var controller = EngineController()

    var body: some Scene {
        MenuBarExtra {
            switch controller.status {
            case .loading: Text("模型加载中…")
            case .ready: Text("就绪 · API :\(controller.settings.port)")
            case .failed(let msg): Text("加载失败: \(msg)").foregroundStyle(.red)
            }
            Divider()
            SettingsLink { Text("设置…") }
            Button("退出") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: controller.status == .ready ? "character.bubble.fill" : "character.bubble")
        }
        .onChange(of: 0) { }  // 占位；真正的启动在 init
        Settings { Text("设置占位，Task 12 实现").padding() }
    }

    init() {
        // @State 在 init 中不可直接用；用静态启动
        Self.bootstrap()
    }

    @MainActor static var shared: EngineController = EngineController()
    @MainActor static func bootstrap() { shared.start() }
}
```

注意：SwiftUI App 生命周期里 `@State` controller 与静态 shared 二选一，实现时统一为 **静态 `shared`**（MenuBarExtra 内读 `GemmaTransApp.shared.status`），上面两处合并修正——执行此任务时以能编译、菜单能显示状态为准。

- [ ] **Step 4: 生成工程并构建**

```bash
cd App && xcodegen generate
xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | tail -5
open build/Build/Products/Debug/GemmaTrans.app
```

Expected: BUILD SUCCEEDED；menu bar 出现图标，状态从"加载中"变"就绪"；`curl http://127.0.0.1:8765/health` 返回 ready（验证 app 内嵌 server 工作）。

- [ ] **Step 5: Commit**

```bash
git add App/
git commit -m "feat: menu bar app 脚手架（引擎加载 + 内嵌 API server）"
```

### Task 12: 设置窗口

**Files:**
- Create: `App/GemmaTrans/SettingsView.swift`
- Modify: `App/GemmaTrans/GemmaTransApp.swift`（Settings scene 换成 SettingsView）

- [ ] **Step 1: 实现 SettingsView**

```swift
// App/GemmaTrans/SettingsView.swift
import SwiftUI
import GemmaTransKit
import KeyboardShortcuts

struct SettingsView: View {
    @State private var settings = AppSettings.load()
    @State private var saved = false

    var body: some View {
        Form {
            Section("模型") {
                HStack {
                    TextField("模型路径", text: $settings.modelPath)
                    Button("选择…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = []
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.modelPath = url.path
                        }
                    }
                }
                Link("下载 Gemma 4 E4B (.litertlm)",
                     destination: URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm")!)
            }
            Section("翻译") {
                TextField("中文翻译为（语言代码）", text: $settings.targetForChinese)
                TextField("其他语言翻译为", text: $settings.targetDefault)
            }
            Section("API") {
                TextField("端口", value: $settings.port, format: .number)
            }
            Section("热键") {
                KeyboardShortcuts.Recorder("划词翻译", name: .translateSelection)
            }
            Button("保存（重启 app 生效）") {
                settings.save()
                saved = true
            }
            if saved { Text("已保存").foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
```

（`KeyboardShortcuts.Name.translateSelection` 在 Task 15 定义；本任务先定义占位于 HotkeyCenter.swift：`extension KeyboardShortcuts.Name { static let translateSelection = Self("translateSelection", default: .init(.d, modifiers: [.option])) }`，文件本任务一并创建，只含这一段。）

- [ ] **Step 2: 构建 + 手动验证**

Run: `cd App && xcodegen generate && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build && open build/Build/Products/Debug/GemmaTrans.app`
Expected: 菜单点"设置…"出窗口，改端口保存，重启 app 后 `curl` 新端口生效。

- [ ] **Step 3: Commit**

```bash
git add App/
git commit -m "feat: 设置窗口（模型路径/语言/端口/热键）"
```

### Task 13: SelectionReader（AX 取词 + ⌘C 兜底）

**Files:**
- Create: `App/GemmaTrans/SelectionReader.swift`

- [ ] **Step 1: 实现**

```swift
// App/GemmaTrans/SelectionReader.swift
import AppKit
import ApplicationServices

enum SelectionReader {
    /// 读取当前前台 app 的选中文本。先 AX，失败则模拟 ⌘C（保存并恢复剪贴板）。
    static func read() async -> String? {
        if let s = axSelectedText(), !s.isEmpty { return s }
        return await copySelectedText()
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func promptForPermission() {
        let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let text = selectedRef as? String else { return nil }
        return text
    }

    private static func copySelectedText() async -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        let beforeCount = pasteboard.changeCount

        // 模拟 ⌘C
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)  // C
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // 最多等 300ms 剪贴板变化
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != beforeCount { break }
        }
        let text = pasteboard.changeCount != beforeCount ? pasteboard.string(forType: .string) : nil

        // 恢复剪贴板
        pasteboard.clearContents()
        pasteboard.writeObjects(savedItems)
        return text
    }
}
```

- [ ] **Step 2: 手动验证（无法单测，依赖系统权限与前台 app）**

构建运行 app → 系统设置授予"辅助功能"权限 → 在 Safari 选中一段文字，临时在菜单加一个"测试取词"按钮调 `SelectionReader.read()` 并 print（验证后删除按钮）→ 分别在原生 app（备忘录）和 Electron app（如 VS Code）验证两条路径。
Expected: 两种 app 都能取到文字；剪贴板原内容不丢。

- [ ] **Step 3: Commit**

```bash
git add App/
git commit -m "feat: 划词取词（AX + ⌘C 兜底，剪贴板恢复）"
```

### Task 14: 浮窗（流式译文 NSPanel）

**Files:**
- Create: `App/GemmaTrans/TranslationPanel.swift`

- [ ] **Step 1: 实现**

```swift
// App/GemmaTrans/TranslationPanel.swift
import SwiftUI
import AppKit
import GemmaTransKit

@MainActor
final class TranslationPanel {
    static let shared = TranslationPanel()
    private var panel: NSPanel?

    func show(text: String, engine: TranslationEngine) {
        let model = TranslationViewModel()
        let view = TranslationView(model: model, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentViewController = hosting
        panel.hidesOnDeactivate = false

        let mouse = NSEvent.mouseLocation
        panel.setFrameTopLeftPoint(NSPoint(x: mouse.x + 8, y: mouse.y - 8))
        self.panel?.close()
        self.panel = panel
        panel.orderFrontRegardless()

        model.start(text: text, engine: engine)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

@MainActor @Observable
final class TranslationViewModel {
    var output = ""
    var status = ""
    var error: String?
    private var task: Task<Void, Never>?

    func start(text: String, engine: TranslationEngine) {
        status = "翻译中…"
        task = Task {
            do {
                let result = try await engine.translate(text, target: nil)
                if result.truncated { status = "（超长已截断）翻译中…" }
                for try await chunk in result.chunks {
                    output += chunk
                }
                status = "\(result.detected) → \(result.target)"
            } catch {
                self.error = "\(error)"
                status = ""
            }
        }
    }
}

struct TranslationView: View {
    let model: TranslationViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(model.error ?? (model.output.isEmpty ? "…" : model.output))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.output, forType: .string)
                }
                .disabled(model.output.isEmpty)
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: 360, height: 160)
    }
}
```

- [ ] **Step 2: 构建验证编译**

Run: `cd App && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED（功能联调在 Task 15 热键接通后）

- [ ] **Step 3: Commit**

```bash
git add App/
git commit -m "feat: 翻译浮窗（流式渲染/复制/Esc 关闭）"
```

### Task 15: 热键接通 + 权限引导（端到端）

**Files:**
- Modify: `App/GemmaTrans/HotkeyCenter.swift`
- Modify: `App/GemmaTrans/GemmaTransApp.swift`

- [ ] **Step 1: HotkeyCenter 完整实现**

```swift
// App/GemmaTrans/HotkeyCenter.swift
import AppKit
import KeyboardShortcuts
import GemmaTransKit

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection", default: .init(.d, modifiers: [.option]))
}

@MainActor
enum HotkeyCenter {
    static func install(controller: EngineController) {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) {
            Task { await handle(controller: controller) }
        }
    }

    static func handle(controller: EngineController) async {
        guard SelectionReader.hasAccessibilityPermission else {
            SelectionReader.promptForPermission()
            return
        }
        guard case .ready = controller.status, let engine = controller.engine else {
            NSSound.beep()
            return
        }
        guard let text = await SelectionReader.read(), !text.isEmpty else {
            TranslationPanel.shared.showMessage("未检测到选中文本")
            return
        }
        TranslationPanel.shared.show(text: text, engine: engine)
    }
}
```

`TranslationPanel` 增加便捷方法：

```swift
func showMessage(_ message: String) {
    // 复用 show 的面板逻辑，直接显示一条提示，1.5 秒后自动关闭
    let model = TranslationViewModel()
    model.output = message
    // …创建 panel 同 show()，并:
    Task { try? await Task.sleep(for: .seconds(1.5)); self.close() }
}
```

（实现时把 panel 创建逻辑抽成私有方法 `makePanel(model:)` 供 `show` 与 `showMessage` 复用，避免复制粘贴。）

GemmaTransApp 启动处调用 `HotkeyCenter.install(controller: Self.shared)`。

- [ ] **Step 2: 端到端验证（M2 验收）**

构建并运行 app →
1. 首次按 `⌥D`：弹系统"辅助功能"授权 → 系统设置勾选 GemmaTrans → 重启 app
2. Safari 选中英文段落按 `⌥D`：浮窗流式出现中文译文，Esc 关闭
3. 备忘录选中中文按 `⌥D`：流式英文译文
4. 不选任何文字按 `⌥D`：提示"未检测到选中文本"
5. 同时 `curl /translate` 确认 HTTP 与热键互不干扰（串行排队）

Expected: 全部符合。

- [ ] **Step 3: Commit**

```bash
git add App/
git commit -m "feat: 全局热键划词翻译端到端打通——M2 验收通过"
```

### Task 16: 文档收尾

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 补 README 的 App 章节**

包含：XcodeGen 构建命令（Task 11 原文）、辅助功能授权步骤、热键默认值与修改方式、与 CLI serve 的关系（app 内嵌 server，二者跑一个即可，端口冲突提示）。

- [ ] **Step 2: 全量回归**

Run: `swift test && cd App && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: 测试全过 + BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README 完整使用文档"
```

---

## 风险与中止条件

- **Task 1/2 是关键路径**：LiteRT-LM SPM 解析失败或 spike 跑不通 → 停止，与用户确认切换 MLX-Swift（仅替换 `TranslationEngine` 内部实现与 Package.swift 依赖，协议与其余任务不变）。
- LiteRT-LM API 签名与文档不符 → spike 内校准，并同步修正 Task 5 代码后再继续。
- FlyingFox `listeningAddress` 枚举形态 / PopClip Config.yaml 键名等小出入 → 对照源码/官方文档修正，不视为计划失败。
