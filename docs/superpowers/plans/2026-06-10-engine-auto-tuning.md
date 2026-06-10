# 引擎参数自动调优 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按物理内存分档 + 加载时可用内存降档，自动推导 KV cache 与输入上限；设置页可手动覆盖。

**Architecture:** Kit 新增两个独立小单元——`EngineTuning`（纯函数档位表，可全表单测）与 `SystemMemory`（mach host_statistics64 读可用内存）；`TranslationEngine.load()` 在自动模式下解析出 `resolvedTuning` 并用于 EngineConfig 与截断；设置页加"性能"区。

**Tech Stack:** Swift 6、mach kernel API（host_statistics64）、现有 swift-testing 测试栈。

**Spec:** `docs/superpowers/specs/2026-06-10-engine-auto-tuning-design.md`

---

## 文件结构

```
Sources/GemmaTransKit/EngineTuning.swift     (Task 1: 档位纯函数)
Sources/GemmaTransKit/SystemMemory.swift     (Task 2: 内存读取)
Sources/GemmaTransKit/AppSettings.swift      (Task 3: autoTuning/manualMaxNumTokens)
Sources/GemmaTransKit/TranslationEngine.swift (Task 3: resolvedTuning 接入)
App/GemmaTrans/SettingsView.swift            (Task 4: 性能区)
Tests/GemmaTransKitTests/EngineTuningTests.swift  (Task 1)
Tests/GemmaTransKitTests/SystemMemoryTests.swift  (Task 2)
README.md                                    (Task 4)
```

### Task 1: EngineTuning 纯函数（TDD）

**Files:**
- Create: `Sources/GemmaTransKit/EngineTuning.swift`
- Test: `Tests/GemmaTransKitTests/EngineTuningTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Tests/GemmaTransKitTests/EngineTuningTests.swift
import Testing
@testable import GemmaTransKit

@Suite struct EngineTuningTests {
    let GB: UInt64 = 1 << 30
    let model: UInt64 = 4 << 30  // 4GB 模型
    let plenty: UInt64 = 100 << 30

    @Test func tier48GB() {
        let t = EngineTuning.recommended(physicalMemory: 48 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 8192, maxInputChars: 6000))
    }

    @Test func tier32GB() {
        let t = EngineTuning.recommended(physicalMemory: 32 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 4096, maxInputChars: 3000))
    }

    @Test func tierJustBelow32GBFallsTo16Tier() {
        let t = EngineTuning.recommended(physicalMemory: 31 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 2048, maxInputChars: 1500))
    }

    @Test func tier16GB() {
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 2048, maxInputChars: 1500))
    }

    @Test func tierBelow16GB() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 1024, maxInputChars: 700))
    }

    @Test func pressureDowngradesOneTier() {
        // 16GB 物理但只剩 2GB 可用 < 4GB 模型 + 4GB 余量 → 降到最低档
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: 2 * GB, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 1024, maxInputChars: 700))
    }

    @Test func pressureDowngradeStopsAtFloor() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: 1 * GB, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 1024, maxInputChars: 700))
    }

    @Test func unknownAvailableMemoryDoesNotDowngrade() {
        // 读取失败（nil）→ 退化为纯静态分档
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: nil, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 2048, maxInputChars: 1500))
    }

    @Test func bigMachineUnderPressureDropsOneTierOnly() {
        let t = EngineTuning.recommended(physicalMemory: 64 * GB, availableMemory: 2 * GB, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 4096, maxInputChars: 3000))
    }
}
```

- [ ] **Step 2: 跑测确认失败**

Run: `swift test --filter EngineTuningTests`
Expected: FAIL（EngineTuning 未定义）

- [ ] **Step 3: 实现**

```swift
// Sources/GemmaTransKit/EngineTuning.swift
import Foundation

/// 按机器内存推导的引擎参数。纯函数，便于全表单测。
public struct EngineTuning: Sendable, Equatable {
    public let maxNumTokens: Int
    public let maxInputChars: Int

    public init(maxNumTokens: Int, maxInputChars: Int) {
        self.maxNumTokens = maxNumTokens
        self.maxInputChars = maxInputChars
    }

    /// 档位表：物理内存下限（含）→ 参数。顺序从高到低，降档即取下一行。
    static let tiers: [(minRAM: UInt64, tuning: EngineTuning)] = [
        (48 << 30, EngineTuning(maxNumTokens: 8192, maxInputChars: 6000)),
        (32 << 30, EngineTuning(maxNumTokens: 4096, maxInputChars: 3000)),
        (16 << 30, EngineTuning(maxNumTokens: 2048, maxInputChars: 1500)),
        (0,        EngineTuning(maxNumTokens: 1024, maxInputChars: 700)),
    ]

    /// 模型之外的工作余量（KV cache、激活、GPU 缓冲、其他 app）
    static let workspaceBytes: UInt64 = 4 << 30

    /// - Parameter availableMemory: 当前可用内存；nil 表示读取失败，不降档（退化为纯静态分档）
    public static func recommended(
        physicalMemory: UInt64, availableMemory: UInt64?, modelFileSize: UInt64
    ) -> EngineTuning {
        var index = tiers.firstIndex { physicalMemory >= $0.minRAM } ?? tiers.count - 1
        if let available = availableMemory, available < modelFileSize + workspaceBytes {
            index = min(index + 1, tiers.count - 1)
        }
        return tiers[index].tuning
    }
}
```

- [ ] **Step 4: 跑测确认通过**

Run: `swift test --filter EngineTuningTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/EngineTuning.swift Tests/GemmaTransKitTests/EngineTuningTests.swift
git commit -m "feat: EngineTuning 档位纯函数（分档 + 压力降档 + 下限保护）"
```

### Task 2: SystemMemory（mach API）

**Files:**
- Create: `Sources/GemmaTransKit/SystemMemory.swift`
- Test: `Tests/GemmaTransKitTests/SystemMemoryTests.swift`

- [ ] **Step 1: 写失败测试（真实系统冒烟断言，宽松边界）**

```swift
// Tests/GemmaTransKitTests/SystemMemoryTests.swift
import Testing
@testable import GemmaTransKit

@Suite struct SystemMemoryTests {
    @Test func physicalMatchesProcessInfo() {
        #expect(SystemMemory.physical() == ProcessInfo.processInfo.physicalMemory)
    }

    @Test func availableIsPositiveAndSane() throws {
        let available = try #require(SystemMemory.available())
        #expect(available > 0)
        #expect(available <= SystemMemory.physical())
    }
}
```

（需要 `import Foundation` 供 ProcessInfo。）

- [ ] **Step 2: 跑测确认失败**

Run: `swift test --filter SystemMemoryTests`
Expected: FAIL（SystemMemory 未定义）

- [ ] **Step 3: 实现**

```swift
// Sources/GemmaTransKit/SystemMemory.swift
import Foundation
import Darwin

public enum SystemMemory {
    public static func physical() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// 可回收给新分配的内存（free + inactive 页）。读取失败返回 nil。
    public static func available() -> UInt64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        return (UInt64(info.free_count) + UInt64(info.inactive_count)) * pageSize
    }
}
```

- [ ] **Step 4: 跑测确认通过**

Run: `swift test --filter SystemMemoryTests`
Expected: PASS（2 个测试）

- [ ] **Step 5: Commit**

```bash
git add Sources/GemmaTransKit/SystemMemory.swift Tests/GemmaTransKitTests/SystemMemoryTests.swift
git commit -m "feat: SystemMemory 可用内存读取（host_statistics64）"
```

### Task 3: 引擎与设置接入

**Files:**
- Modify: `Sources/GemmaTransKit/AppSettings.swift`
- Modify: `Sources/GemmaTransKit/TranslationEngine.swift`

- [ ] **Step 1: AppSettings 增加 autoTuning 与 manualMaxNumTokens**

init 参数列表追加（带默认值）、属性、load()/save() 各加两行：

```swift
public var autoTuning: Bool
public var manualMaxNumTokens: Int

// init 参数追加: autoTuning: Bool = true, manualMaxNumTokens: Int = 2048

// load() 追加（bool 缺省时默认 true，不能直接用 bool(forKey:)）:
if d.object(forKey: "autoTuning") != nil { s.autoTuning = d.bool(forKey: "autoTuning") }
if d.integer(forKey: "manualMaxNumTokens") > 0 { s.manualMaxNumTokens = d.integer(forKey: "manualMaxNumTokens") }
if d.integer(forKey: "maxInputChars") > 0 { s.maxInputChars = d.integer(forKey: "maxInputChars") }

// save() 追加:
d.set(autoTuning, forKey: "autoTuning")
d.set(manualMaxNumTokens, forKey: "manualMaxNumTokens")
d.set(maxInputChars, forKey: "maxInputChars")
```

- [ ] **Step 2: TranslationEngine 接入 resolvedTuning**

```swift
// 属性区追加:
private var resolvedTuning: EngineTuning?
/// 设置页展示用
public var currentTuning: EngineTuning? { resolvedTuning }

// load() 中 EngineConfig 之前:
let tuning: EngineTuning
if settings.autoTuning {
    let modelSize = (try? FileManager.default.attributesOfItem(atPath: settings.modelPath)[.size] as? NSNumber)
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

// EngineConfig 的 maxNumTokens: 2048 改为 tuning.maxNumTokens（原 2048 注释删除）

// translate() 中 settings.maxInputChars 改为:
let maxChars = resolvedTuning?.maxInputChars ?? settings.maxInputChars
let truncated = trimmed.count > maxChars
let input = truncated ? String(trimmed.prefix(maxChars)) : trimmed
```

- [ ] **Step 3: 全量测试（含引擎集成）**

Run: `swift test`
Expected: 全部 PASS。本机 16GB 空闲时自动档应取 2048/1500，引擎集成测试行为不变；若本机当时内存紧张降到 1024 也属正确行为（测试只断言翻译成功，不断言档位）。

- [ ] **Step 4: Commit**

```bash
git add Sources/GemmaTransKit/
git commit -m "feat: 引擎按机器配置自动调优（autoTuning 默认开，手动可覆盖）"
```

### Task 4: 设置页性能区 + README

**Files:**
- Modify: `App/GemmaTrans/SettingsView.swift`
- Modify: `README.md`

- [ ] **Step 1: SettingsView 在"API"Section 后插入性能区**

```swift
Section("性能") {
    Toggle("自动配置（按内存推荐）", isOn: $settings.autoTuning)
    if settings.autoTuning {
        let auto = EngineTuning.recommended(
            physicalMemory: SystemMemory.physical(),
            availableMemory: SystemMemory.available(),
            modelFileSize: 4 << 30
        )
        Text("当前推荐：KV cache \(auto.maxNumTokens) tokens · 输入上限 \(auto.maxInputChars) 字符")
            .foregroundStyle(.secondary)
    } else {
        TextField("KV cache (tokens)", value: $settings.manualMaxNumTokens,
                  format: .number.grouping(.never))
        TextField("输入上限（字符）", value: $settings.maxInputChars,
                  format: .number.grouping(.never))
    }
}
```

- [ ] **Step 2: 构建 app**

Run: `cd App && xcodegen generate && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: README 输入上限描述更新**

把 `/translate` 表中 `text` 行改为：

```
| `text` | string | 必填，待翻译文本（超长截断；上限随机器自动调优，16GB 机器默认 1500 字符，可在设置中手动覆盖） |
```

并在"Menu bar app"一节末尾追加一行：

```
- 设置"性能"区默认按机器内存自动配置 KV cache 与输入上限（加载时还会按当前可用内存降档），也可手动覆盖
```

- [ ] **Step 4: 重启 app 真机验证 + Commit**

Run: `pkill -x GemmaTrans; open App/build/Build/Products/Debug/GemmaTrans.app`，health ready 后翻译一句，查看 `~/Library/Logs/GemmaTrans/gemmatrans.log` 应有 `auto tuning: kv=2048 input=1500` 行（空闲时）。

```bash
git add App/GemmaTrans/SettingsView.swift README.md
git commit -m "feat: 设置页性能区（自动调优开关 + 手动覆盖）"
```

---

## 自查

- 覆盖 spec 全部点：档位表 ✓（Task 1）、降档与下限 ✓、nil 容错 ✓、模型大小读取失败按 4GB ✓（Task 3 `?? (4 << 30)`）、GTLog 记录 ✓、设置 UI ✓、引擎集成测试不破坏 ✓。
- 类型一致：`EngineTuning.recommended(physicalMemory:availableMemory:modelFileSize:)` 三处调用签名一致；`currentTuning` 为 actor 属性（外部 `await` 访问）。
