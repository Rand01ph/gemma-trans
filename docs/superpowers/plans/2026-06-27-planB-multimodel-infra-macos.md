# Plan B — 多模型基础设施 + macOS 配置页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 macOS 用户在配置页下载、切换、删除多个本地模型；架构落 `GemmaTransKit` 供 iOS 复用。

**Architecture:** 引入策展数据表 `ModelCatalog` 作为「模型 → 仓库/family/体积/默认参数」的单一真相源；
`AppSettings.selectedModelID` 记录活跃选择（`"auto"` 或某 catalog id）；`InstalledModels` 扫描磁盘已下模型；
纯函数 `ModelSwitchGuard` 判定能否切换；`EngineController.switchModel` 在守卫通过时卸旧载新。
本计划独立于 Hy-MT2：catalog 是否含 Hy-MT2 条目由 Plan A 决策门决定，infra 对 family 无偏。

**Tech Stack:** Swift 6 · SwiftUI（macOS）· MLX-Swift · XCTest（`GemmaTransKitTests`）。

## Global Constraints

- 复用既有下载器 `ModelDownloader`（双源、断点续传、`snapshotDirectory(base, repo)` 每模型一目录），不重写。
- 默认行为不变：`selectedModelID == "auto"` 等价于现有 `EngineTuning.recommended` 选 Gemma；存量用户无感。
- 切换守卫：引擎 `isGenerating` 或 `loading` 中、或 `apiStatus == .running` 时禁止切换。
- 纯函数层全部 XCTest 覆盖，沿用 `Tests/GemmaTransKitTests/` 现有风格；下载器既有测试不回归。
- `estimatedBytes` 真值（落盘体积）：Gemma E4B `4_900_000_000`、E2B `3_600_000_000`、
  Hy-MT2-1.8B 4bit `1_100_000_000`、8bit `1_900_000_000`（实现期以实下体积校正）。
- macOS 优先；catalog/settings/installed/guard/engine 落 Kit 与 App 共享层，iOS UI 不在本计划。

---

### Task 1: ModelCatalog 策展表

**Files:**
- Create: `Sources/GemmaTransKit/ModelCatalog.swift`
- Test: `Tests/GemmaTransKitTests/ModelCatalogTests.swift`

**Interfaces:**
- Produces:
  - `public enum ModelFamily: String, Sendable, Codable { case gemma, hunyuanMT2 }`
  - `public struct ModelCatalogEntry: Sendable, Equatable, Identifiable { public let id, displayName, repo: String; public let family: ModelFamily; public let estimatedBytes: UInt64; public let defaultMaxTokens, defaultMaxInputChars: Int }`
  - `public enum ModelCatalog { public static let autoID = "auto"; public static let entries: [ModelCatalogEntry]; public static func entry(id: String) -> ModelCatalogEntry? }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GemmaTransKit

final class ModelCatalogTests: XCTestCase {
    func test_entries_haveUniqueStableIDs() {
        let ids = ModelCatalog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "catalog id 必须唯一")
        XCTAssertTrue(ids.contains("gemma-e4b-4bit"))
        XCTAssertTrue(ids.contains("gemma-e2b-4bit"))
    }

    func test_entry_lookupByID() {
        let e = ModelCatalog.entry(id: "gemma-e2b-4bit")
        XCTAssertEqual(e?.repo, "mlx-community/gemma-4-e2b-it-4bit")
        XCTAssertEqual(e?.family, .gemma)
        XCTAssertNil(ModelCatalog.entry(id: "nope"))
    }

    func test_autoID_isNotAnEntry() {
        XCTAssertNil(ModelCatalog.entry(id: ModelCatalog.autoID))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelCatalogTests`
Expected: FAIL（`ModelCatalog` 未定义）。

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum ModelFamily: String, Sendable, Codable { case gemma, hunyuanMT2 }

public struct ModelCatalogEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let repo: String
    public let family: ModelFamily
    public let estimatedBytes: UInt64
    public let defaultMaxTokens: Int
    public let defaultMaxInputChars: Int
}

public enum ModelCatalog {
    public static let autoID = "auto"

    public static let entries: [ModelCatalogEntry] = [
        ModelCatalogEntry(id: "gemma-e4b-4bit", displayName: "Gemma 4 E4B (4-bit)",
            repo: "mlx-community/gemma-4-e4b-it-4bit", family: .gemma,
            estimatedBytes: 4_900_000_000, defaultMaxTokens: 2048, defaultMaxInputChars: 1500),
        ModelCatalogEntry(id: "gemma-e2b-4bit", displayName: "Gemma 4 E2B (4-bit)",
            repo: "mlx-community/gemma-4-e2b-it-4bit", family: .gemma,
            estimatedBytes: 3_600_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 700),
        // Hy-MT2 两条目：Plan A 决策门通过后保留；不过则删除这两行（infra 不依赖它们）。
        ModelCatalogEntry(id: "hymt2-4bit", displayName: "Hy-MT2 1.8B (4-bit · 翻译专用)",
            repo: "mlx-community/Hy-MT2-1.8B-4bit", family: .hunyuanMT2,
            estimatedBytes: 1_100_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 1500),
        ModelCatalogEntry(id: "hymt2-8bit", displayName: "Hy-MT2 1.8B (8-bit · 翻译专用)",
            repo: "mlx-community/Hy-MT2-1.8B-8bit", family: .hunyuanMT2,
            estimatedBytes: 1_900_000_000, defaultMaxTokens: 1024, defaultMaxInputChars: 1500),
    ]

    public static func entry(id: String) -> ModelCatalogEntry? {
        entries.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelCatalogTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/ModelCatalog.swift Tests/GemmaTransKitTests/ModelCatalogTests.swift
git commit -m "feat: ModelCatalog 策展表（模型→仓库/family/体积/默认参数单一真相源）"
```

---

### Task 2: AppSettings 增加 selectedModelID

**Files:**
- Modify: `Sources/GemmaTransKit/AppSettings.swift`
- Test: `Tests/GemmaTransKitTests/AppSettingsTests.swift`（已存在，追加用例）

**Interfaces:**
- Produces: `AppSettings.selectedModelID: String`（默认 `ModelCatalog.autoID`）；随 `load`/`save` 持久化。
- Consumes: `ModelCatalog.autoID`（Task 1）。

- [ ] **Step 1: Write the failing test**

```swift
func test_selectedModelID_defaultsToAuto() {
    XCTAssertEqual(AppSettings().selectedModelID, "auto")
}

func test_selectedModelID_roundTripsThroughDefaults() {
    let suite = "test.selectedModel.\(UUID().uuidString)"
    var s = AppSettings()
    s.selectedModelID = "hymt2-8bit"
    s.save(suiteName: suite)
    XCTAssertEqual(AppSettings.load(suiteName: suite).selectedModelID, "hymt2-8bit")
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppSettingsTests`
Expected: FAIL（`selectedModelID` 未定义）。

- [ ] **Step 3: Implement**

在 `AppSettings` 加属性、init 参数、load/save：
```swift
// 属性区（其他属性后）
/// 活跃模型选择："auto"=按内存选 Gemma；否则为 ModelCatalog 条目 id
public var selectedModelID: String

// init 增参（末尾，带默认值，保持既有调用兼容）
selectedModelID: String = "auto"
// init 体内
self.selectedModelID = selectedModelID

// load() 内追加
if let v = d.string(forKey: "selectedModelID"), !v.isEmpty { s.selectedModelID = v }

// save() 内追加
d.set(selectedModelID, forKey: "selectedModelID")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/AppSettings.swift Tests/GemmaTransKitTests/AppSettingsTests.swift
git commit -m "feat: AppSettings.selectedModelID（活跃模型选择，默认 auto）"
```

---

### Task 3: 活跃模型解析（Auto/显式 → 具体 entry + tuning）

**Files:**
- Create: `Sources/GemmaTransKit/ActiveModelResolver.swift`
- Test: `Tests/GemmaTransKitTests/ActiveModelResolverTests.swift`

**Interfaces:**
- Consumes: `ModelCatalog`（Task 1）、`AppSettings.selectedModelID`（Task 2）、
  `EngineTuning.recommended`（既有 `EngineTuning.swift`）。
- Produces:
  - `public struct ResolvedModel: Sendable, Equatable { public let entry: ModelCatalogEntry; public let tuning: EngineTuning }`
  - `public enum ActiveModelResolver { public static func resolve(selectedID: String, physicalMemory: UInt64, availableMemory: UInt64?) -> ResolvedModel }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GemmaTransKit

final class ActiveModelResolverTests: XCTestCase {
    // Auto：按内存选 Gemma，entry 与 recommended 的 variant 对应
    func test_auto_picksGemmaByRAM_highMem() {
        let r = ActiveModelResolver.resolve(selectedID: "auto",
            physicalMemory: 64 << 30, availableMemory: 60 << 30)
        XCTAssertEqual(r.entry.id, "gemma-e4b-4bit")
        XCTAssertEqual(r.tuning.maxTokens, 4096) // 48GB+ 档
    }

    func test_auto_lowMem_picksE2B() {
        let r = ActiveModelResolver.resolve(selectedID: "auto",
            physicalMemory: 8 << 30, availableMemory: 4 << 30)
        XCTAssertEqual(r.entry.id, "gemma-e2b-4bit")
    }

    // 显式选择：直接采用该 entry；tuning 用其默认参数
    func test_explicit_usesEntryDefaults() {
        let r = ActiveModelResolver.resolve(selectedID: "hymt2-8bit",
            physicalMemory: 16 << 30, availableMemory: 10 << 30)
        XCTAssertEqual(r.entry.id, "hymt2-8bit")
        XCTAssertEqual(r.tuning.variant, .gemma4E2B4bit) // 见实现说明
        XCTAssertEqual(r.tuning.maxTokens, 1024)
        XCTAssertEqual(r.tuning.maxInputChars, 1500)
    }

    // 未知 id 回退 auto（防 settings 脏数据）
    func test_unknownID_fallsBackToAuto() {
        let r = ActiveModelResolver.resolve(selectedID: "garbage",
            physicalMemory: 64 << 30, availableMemory: 60 << 30)
        XCTAssertEqual(r.entry.family, .gemma)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ActiveModelResolverTests`
Expected: FAIL（未定义）。

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct ResolvedModel: Sendable, Equatable {
    public let entry: ModelCatalogEntry
    public let tuning: EngineTuning
}

public enum ActiveModelResolver {
    public static func resolve(
        selectedID: String, physicalMemory: UInt64, availableMemory: UInt64?
    ) -> ResolvedModel {
        // Auto 或未知 id：按内存选 Gemma（沿用既有分档），映射到对应 catalog 条目
        if selectedID == ModelCatalog.autoID || ModelCatalog.entry(id: selectedID) == nil {
            let t = EngineTuning.recommended(
                physicalMemory: physicalMemory, availableMemory: availableMemory)
            let id = (t.variant == .gemma4E4B4bit) ? "gemma-e4b-4bit" : "gemma-e2b-4bit"
            return ResolvedModel(entry: ModelCatalog.entry(id: id)!, tuning: t)
        }
        // 显式选择：用 entry 默认参数构造 tuning。variant 字段仅 Gemma 加载路径用到，
        // 非 Gemma family 时填一个占位（.gemma4E2B4bit），加载分发以 entry.family 为准。
        let e = ModelCatalog.entry(id: selectedID)!
        let variant: ModelVariant = (e.id == "gemma-e4b-4bit") ? .gemma4E4B4bit : .gemma4E2B4bit
        let tuning = EngineTuning(variant: variant,
            maxTokens: e.defaultMaxTokens, maxInputChars: e.defaultMaxInputChars)
        return ResolvedModel(entry: e, tuning: tuning)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ActiveModelResolverTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/ActiveModelResolver.swift Tests/GemmaTransKitTests/ActiveModelResolverTests.swift
git commit -m "feat: ActiveModelResolver（auto 按内存选 Gemma / 显式选用 entry 默认参数）"
```

---

### Task 4: InstalledModels 磁盘扫描与删除

**Files:**
- Create: `Sources/GemmaTransKit/InstalledModels.swift`
- Test: `Tests/GemmaTransKitTests/InstalledModelsTests.swift`

**Interfaces:**
- Consumes: `ModelCatalog`（Task 1）、`ModelDownloader.snapshotDirectory`/`.isComplete`（既有）。
- Produces:
  - `public struct InstalledModel: Sendable, Equatable { public let id: String; public let bytesOnDisk: UInt64 }`
  - `public enum InstalledModels { public static func scan(base: URL) -> [InstalledModel]; public static func delete(id: String, base: URL) throws }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GemmaTransKit

final class InstalledModelsTests: XCTestCase {
    private func tempBase() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // 在 base 下伪造某 catalog 条目的快照目录（含完成标记），scan 应识别
    func test_scan_findsCompletedSnapshot() throws {
        let base = tempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let repo = ModelCatalog.entry(id: "gemma-e2b-4bit")!.repo
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = dir.appendingPathComponent("model.safetensors")
        try Data(repeating: 0, count: 2048).write(to: payload)
        // 完成标记：文件名→字节数（与 ModelDownloader.isComplete 一致）
        let marker = ["model.safetensors": Int64(2048)]
        try JSONEncoder().encode(marker).write(to: dir.appendingPathComponent(".download-complete"))

        let found = InstalledModels.scan(base: base)
        XCTAssertEqual(found.map(\.id), ["gemma-e2b-4bit"])
        XCTAssertGreaterThanOrEqual(found.first!.bytesOnDisk, 2048)
    }

    func test_scan_ignoresIncompleteOrUnknown() throws {
        let base = tempBase(); defer { try? FileManager.default.removeItem(at: base) }
        // 不完整（无标记）的已知仓库目录
        let repo = ModelCatalog.entry(id: "gemma-e4b-4bit")!.repo
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10).write(to: dir.appendingPathComponent("partial.bin"))
        XCTAssertTrue(InstalledModels.scan(base: base).isEmpty)
    }

    func test_delete_removesSnapshot() throws {
        let base = tempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let repo = ModelCatalog.entry(id: "gemma-e2b-4bit")!.repo
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: repo)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try InstalledModels.delete(id: "gemma-e2b-4bit", base: base)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter InstalledModelsTests`
Expected: FAIL（未定义）。

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct InstalledModel: Sendable, Equatable {
    public let id: String
    public let bytesOnDisk: UInt64
}

public enum InstalledModels {
    /// 遍历 catalog，凡在 base 下有完整快照（ModelDownloader.isComplete）者计入，附目录体积。
    public static func scan(base: URL) -> [InstalledModel] {
        ModelCatalog.entries.compactMap { entry in
            let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
            guard ModelDownloader.isComplete(dir) else { return nil }
            return InstalledModel(id: entry.id, bytesOnDisk: directorySize(dir))
        }
    }

    public static func delete(id: String, base: URL) throws {
        guard let entry = ModelCatalog.entry(id: id) else { return }
        let dir = ModelDownloader.snapshotDirectory(in: base, repo: entry.repo)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private static func directorySize(_ dir: URL) -> UInt64 {
        guard let en = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in en {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += UInt64(size)
        }
        return total
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter InstalledModelsTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/InstalledModels.swift Tests/GemmaTransKitTests/InstalledModelsTests.swift
git commit -m "feat: InstalledModels 磁盘扫描已下模型 + 体积 + 删除"
```

---

### Task 5: ModelSwitchGuard 切换守卫（纯函数）

**Files:**
- Create: `Sources/GemmaTransKit/ModelSwitchGuard.swift`
- Test: `Tests/GemmaTransKitTests/ModelSwitchGuardTests.swift`

**Interfaces:**
- Produces:
  - `public enum SwitchBlock: Sendable, Equatable { case generating, loading, apiRunning }`
  - `public enum ModelSwitchGuard { public static func blockReason(isGenerating: Bool, isLoading: Bool, apiRunning: Bool) -> SwitchBlock? }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GemmaTransKit

final class ModelSwitchGuardTests: XCTestCase {
    func test_idle_allowsSwitch() {
        XCTAssertNil(ModelSwitchGuard.blockReason(
            isGenerating: false, isLoading: false, apiRunning: false))
    }
    func test_generating_blocks() {
        XCTAssertEqual(.generating, ModelSwitchGuard.blockReason(
            isGenerating: true, isLoading: false, apiRunning: false))
    }
    func test_loading_blocks() {
        XCTAssertEqual(.loading, ModelSwitchGuard.blockReason(
            isGenerating: false, isLoading: true, apiRunning: false))
    }
    func test_apiRunning_blocks() {
        XCTAssertEqual(.apiRunning, ModelSwitchGuard.blockReason(
            isGenerating: false, isLoading: false, apiRunning: true))
    }
    // 优先级：生成 > 加载 > API（稳定的提示文案）
    func test_priority_generatingFirst() {
        XCTAssertEqual(.generating, ModelSwitchGuard.blockReason(
            isGenerating: true, isLoading: true, apiRunning: true))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ModelSwitchGuardTests`
Expected: FAIL。

- [ ] **Step 3: Implement**

```swift
public enum SwitchBlock: Sendable, Equatable { case generating, loading, apiRunning }

public enum ModelSwitchGuard {
    public static func blockReason(
        isGenerating: Bool, isLoading: Bool, apiRunning: Bool
    ) -> SwitchBlock? {
        if isGenerating { return .generating }
        if isLoading { return .loading }
        if apiRunning { return .apiRunning }
        return nil
    }
}

public extension SwitchBlock {
    var message: String {
        switch self {
        case .generating: "正在翻译，请稍候再切换模型"
        case .loading: "模型加载中，请稍候再切换"
        case .apiRunning: "本地 API 运行中，请先在设置里关闭 API 再切换模型"
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ModelSwitchGuardTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/ModelSwitchGuard.swift Tests/GemmaTransKitTests/ModelSwitchGuardTests.swift
git commit -m "feat: ModelSwitchGuard 切换守卫（翻译中/加载中/API 运行禁切）"
```

---

### Task 6: TranslationEngine 按 ResolvedModel 加载（含 family 分发）

**Files:**
- Modify: `Sources/GemmaTransKit/TranslationEngine.swift`（`load(...)` 与 variant→config 分发）

**Interfaces:**
- Consumes: `ResolvedModel`（Task 3）、`ModelCatalog`（Task 1）、（若 Plan A 通过）`registerHunyuanIfNeeded()`。
- Produces: `TranslationEngine.load(resolved: ResolvedModel, cacheDirectory: URL?, modelSource: ModelSource, useCPU: Bool, progress:)` —
  以 `resolved.entry.repo` 为下载/加载仓库，按 `resolved.entry.family` 分发加载方式。

- [ ] **Step 1: 引入按 entry 的加载入口（保留旧签名为薄封装，避免一次性改穿全调用方）**

在 `load(...)` 内部，把「推导 tuning + variant→repo」替换为「接收 `resolved`，用 `resolved.entry.repo` 做
快照目录与下载，用 `resolved.tuning` 做 `resolvedTuning`」。family 分发：
```swift
let repo = resolved.entry.repo
// ... 既有 snapshotDir / 下载 / isComplete 逻辑，repo 改用上面这个 ...
switch resolved.entry.family {
case .gemma:
    // 既有 Gemma 路径：LLMRegistry 配置 + #huggingFaceLoadModelContainer / loadModelContainer(from:)
    loaded = try await loadModelContainer(from: snapshotDir, using: #huggingFaceTokenizerLoader())
case .hunyuanMT2:
    await registerHunyuanIfNeeded()   // Plan A 产出；未接入前此分支不可达（catalog 无 Hy-MT2）
    loaded = try await loadModelContainer(from: snapshotDir, using: #huggingFaceTokenizerLoader())
}
```
保留旧 `load(cacheDirectory:modelSource:tuningOverride:useCPU:progress:)`，内部据入参构造 `ResolvedModel`
后转调新入口，使 `EngineController`/`EngineHolder` 现有调用先不破。

- [ ] **Step 2: 编译**

Run: `swift build --target GemmaTransKit`
Expected: 成功。

- [ ] **Step 3: 回归既有引擎/调优测试**

Run: `swift test`
Expected: 现有 `EngineTuningTests` 等全过（Gemma 路径行为不变）。

- [ ] **Step 4: Commit**

```bash
git add Sources/GemmaTransKit/TranslationEngine.swift
git commit -m "feat: TranslationEngine 按 ResolvedModel 加载 + family 分发（Gemma 路径不变）"
```

---

### Task 7: EngineController 切换模型 + 已装/活跃状态（macOS）

**Files:**
- Modify: `App/GemmaTrans/EngineController.swift`

**Interfaces:**
- Consumes: `ActiveModelResolver`、`InstalledModels`、`ModelSwitchGuard`、`ModelDownloader`、`ModelCatalog`。
- Produces（`@MainActor @Observable`）：
  - `var selectedModelID: String`（镜像 settings，UI 绑定）
  - `func installedModels() -> [InstalledModel]`
  - `func switchModel(to id: String) -> SwitchBlock?`（守卫不过返回原因且不切；过则置 loading 并重载）
  - `func deleteModel(id: String)`（活跃中禁删）

- [ ] **Step 1: 抽出可复用的加载流程**

把 `start()` 内的加载封成 `private func loadActive()`：读 `settings.selectedModelID` →
`ActiveModelResolver.resolve(...)` → `engine.load(resolved:...)`，状态机沿用 `.loading/.downloading/.ready/.failed`。
`start()` 调 `loadActive()`。

- [ ] **Step 2: 实现 switchModel（守卫 + 卸旧载新）**

```swift
func switchModel(to id: String) -> SwitchBlock? {
    let apiRunning = { if case .running = apiStatus { return true } else { return false } }()
    let generating = engine.map { e in /* await 不便：用最近一次 isGenerating 镜像，见 Step 3 */ } ?? false
    if let block = ModelSwitchGuard.blockReason(
        isGenerating: generatingMirror, isLoading: engineStatus == .loading, apiRunning: apiRunning) {
        return block
    }
    settings.selectedModelID = id
    settings.save()
    self.selectedModelID = id
    engineStatus = .loading
    Task {
        await engine?.unload()      // model = nil + clearCache（见 Step 4）
        await loadActive()
    }
    return nil
}
```

- [ ] **Step 3: 维护 isGenerating 镜像（actor 属性不能在 MainActor 同步读）**

`TranslationEngine` 已有 `public var isGenerating: Bool`（actor）。在每次 `translate/process`
开始与结束时通过既有回调或轮询更新一个 `@MainActor` 镜像 `generatingMirror`；
最小实现：`switchModel` 前 `Task { generatingMirror = await engine?.isGenerating ?? false }` 预热，
或将守卫判定移入一个 `async func switchModel(...) async -> SwitchBlock?` 直接 `await engine?.isGenerating`。
**采用 async 版**以避免镜像竞态：
```swift
func switchModel(to id: String) async -> SwitchBlock? {
    let generating = await engine?.isGenerating ?? false
    // ...其余同 Step 2，去掉 generatingMirror...
}
```

- [ ] **Step 4: 引擎加 unload()**

Modify `TranslationEngine`：
```swift
public func unload() {
    model = nil
    MLX.Memory.clearCache()
    GTLog.info("mlx model unloaded (switch)")
}
```

- [ ] **Step 5: deleteModel（活跃中禁删）**

```swift
func deleteModel(id: String) {
    let activeRepo = ActiveModelResolver.resolve(
        selectedID: settings.selectedModelID,
        physicalMemory: SystemMemory.physical(),
        availableMemory: SystemMemory.available()).entry.id
    guard id != activeRepo else { return }   // 活跃中禁删
    try? InstalledModels.delete(id: id, base: Self.modelBase)
}
```
（`Self.modelBase` = `TranslationEngine` 默认模型目录；将其暴露为 Kit 公开静态方法供两端共用。）

- [ ] **Step 6: 编译 + 手测**

Run: `swift build`（App target）
Expected: 成功。手动：切换两个已下 Gemma 档应触发 loading→ready；API 开启时切换被守卫拦下。

- [ ] **Step 7: Commit**

```bash
git add App/GemmaTrans/EngineController.swift Sources/GemmaTransKit/TranslationEngine.swift
git commit -m "feat: EngineController.switchModel/deleteModel + 引擎 unload（守卫+卸旧载新）"
```

---

### Task 8: macOS SettingsView 模型列表 UI

**Files:**
- Modify: `App/GemmaTrans/SettingsView.swift`（替换「模型」Section）

**Interfaces:**
- Consumes: `EngineController.shared`（`selectedModelID`/`installedModels()`/`switchModel`/`deleteModel`/`download`）、
  `ModelCatalog.entries`、`InstalledModels`。

- [ ] **Step 1: 替换「模型」Section 为目录列表**

为 `ModelCatalog.entries` 每条 + 顶部「Auto（按内存推荐）」渲染一行，显示：名称、体积估算、
状态徽标（未下载 / 下载中 N% / 已下 X GB / 活跃中），与按钮：
- 未下载：「下载」→ `EngineController.shared.download(modelID:)`（扩展 download 接受目标 id）
- 已下非活跃：「设为活跃」→ `Task { if let b = await EngineController.shared.switchModel(to: id) { 弹提示 b.message } }`
- 已下非活跃：「删除」→ `EngineController.shared.deleteModel(id:)`
- 活跃中：徽标「活跃」，删除按钮 disabled

切换/下载进行中（`engineStatus == .loading/.downloading`）时，所有「设为活跃」按钮 disabled；
API 运行中时「设为活跃」disabled 并加 help 提示 `SwitchBlock.apiRunning.message`。

- [ ] **Step 2: 下载进度接线**

复用 `EngineController` 的 `.downloading(progress)` 状态，仅对「正在下载的那一项」显示百分比
（控制器记录 `downloadingModelID`）。

- [ ] **Step 3: 编译 + 手测**

Run: `swift build` 并启动 app 打开设置页。
Expected：列表呈现 5 项（含 Auto）；下载一个 E2B → 状态变「已下」；设为活跃 → loading→ready；
开 API 后「设为活跃」置灰且 hover 提示；删除非活跃项目录消失。

- [ ] **Step 4: Commit**

```bash
git add App/GemmaTrans/SettingsView.swift App/GemmaTrans/EngineController.swift
git commit -m "feat: macOS 设置页多模型列表（下载/设为活跃/删除 + 守卫置灰）"
```

---

## Self-Review

**Spec coverage：**
- 策展表 5 项（Auto/Gemma×2/Hy-MT2×2）→ Task 1。
- selectedModelID + 默认 auto → Task 2；Auto=现有 RAM 选 Gemma → Task 3。
- 多模型并存/磁盘扫描/删除 → Task 4；活跃中禁删 → Task 7 Step 5。
- 切换守卫（翻译中/加载中/API 运行）→ Task 5（纯判定）+ Task 7（接线）+ Task 8（置灰）。
- 一键切活跃（卸旧载新）→ Task 6（family 分发加载）+ Task 7（switchModel+unload）。
- macOS UI → Task 8；架构落 Kit 供 iOS 复用 → Task 1-6 全在 `GemmaTransKit`。
- Hy-MT2 条目随 Plan A 决策门可整体删除，infra 不依赖 → Task 1 注释标注。

**Placeholder scan：** 无 TODO/TBD；UI 任务（Task 8）给出结构与绑定而非逐行 SwiftUI（视图非 TDD 单元，合规）。

**Type consistency：** `ModelCatalogEntry`/`ResolvedModel`/`InstalledModel`/`SwitchBlock`/`ModelSwitchGuard.blockReason`/
`ActiveModelResolver.resolve`/`switchModel(to:) async -> SwitchBlock?` 跨 Task 命名一致。
`EngineTuning.recommended` 沿用既有签名。

**已知实现期细化点：**
- Task 7 Step 3：守卫读 actor `isGenerating` → 采用 `async` 版 `switchModel` 直接 `await`，避免镜像竞态。
- `download(modelID:)` 与 `downloadingModelID` 为 Task 7/8 对 `EngineController` 现有 `download/start` 的小扩展。
- `estimatedBytes` 待实下体积校正（Global Constraints 已列估值）。
