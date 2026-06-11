# GemmaTrans iOS v1（接管系统翻译按钮）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS app + TranslationUIProvider 扩展——用户在任意 app 选中文字点系统「翻译」，原地弹出 GemmaTrans 面板流式显示本地 Gemma 译文。

**Architecture:** 复用 GemmaTransKit（引擎/调优/检测/提示词），模型经 HubCache 存入 App Group 共享容器（主 app 下载、扩展读取）。主 app 与扩展进程各持一个 EngineHolder 单例。Task 5/6 是真机 spike 决策门：扩展进程内存额度不足以跑 E2B 时全盘回退快捷指令方案（不在本计划内）。

**Tech Stack:** Swift 6 / SwiftUI / TranslationUIProvider (iOS 18.4+) / ExtensionKit / MLX (mlx-swift-lm) / XcodeGen 2.45+

**关键事实（已核实，编写时不要再猜）:**
- TranslationUIProvider 真实 API（来自 iOS 26.5 SDK swiftinterface）：
  `TranslationUIProviderContext` 有 `inputText: AttributedString?`、`allowsReplacement: Bool`、`finish(translation: AttributedString?)`、`expandSheet()`；场景为 `TranslationUIProviderSelectedTextScene { context in View }`；入口为 `@main class X: TranslationUIProviderExtension`（`required init()`）
- 扩展 Info.plist 标识：`EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.public.translation-ui-provider`（ExtensionKit 扩展，非 NSExtension）
- 模型自定义目录：`HubClient(cache: HubCache(cacheDirectory: url))` + `loadModelContainer(from: #hubDownloader(hub), using: #huggingFaceTokenizerLoader(), configuration:)`（MLXLMCommon 提供，宏在 MLXHuggingFace）
- HubCache 目录布局：`<cacheDirectory>/models--mlx-community--gemma-4-e2b-it-4bit/...`
- EngineTuning 现有最低档（<16GB RAM）就是 E2B/1024/700——iPhone 8GB 自动命中，**无需新增 iOS 档**
- MLX 不支持 iOS 模拟器，一切模型相关验证只能真机；无签名编译检查用 `CODE_SIGNING_ALLOWED=NO`
- xcodeproj 不入库（.gitignore 已忽略 `*.xcodeproj`），每次 `xcodegen generate` 现场生成

---

### Task 1: Package 平台声明 + iOS 档位回归测试

**Files:**
- Modify: `Package.swift:6`
- Modify: `Tests/GemmaTransKitTests/EngineTuningTests.swift`（追加一个用例）

- [ ] **Step 1: 写失败测试——8GB 设备命中 E2B 档**

在 `Tests/GemmaTransKitTests/EngineTuningTests.swift` 现有 suite 内追加：

```swift
    /// iOS 设备档位：A17 Pro+ iPhone 为 8GB RAM，必须命中 E2B/1024/700（iOS spec 依赖此行为）
    @Test func iPhone8GBHitsE2BTier() {
        let t = EngineTuning.recommended(physicalMemory: 8 << 30, availableMemory: nil)
        #expect(t.variant == .gemma4E2B4bit)
        #expect(t.maxTokens == 1024)
        #expect(t.maxInputChars == 700)
    }
```

- [ ] **Step 2: 跑测试确认通过（现有档位表已覆盖，此测试是契约锁定，预期直接绿）**

Run: `swift test --filter EngineTuningTests`
Expected: PASS（若失败说明档位表被人改过，停下来核对 spec）

- [ ] **Step 3: Package.swift 加 iOS 平台**

`Package.swift` 第 6 行改为：

```swift
    platforms: [.macOS(.v14), .iOS(.v18)],
```

- [ ] **Step 4: macOS 回归**

Run: `swift build && swift test`
Expected: 全绿（iOS 平台声明不影响 macOS 构建）

- [ ] **Step 5: Kit 的 iOS 交叉编译检查**

Run（repo 根目录）: `xcodebuild -scheme GemmaTransKit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -skipMacroValidation build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`（Kit 全部源文件是 Foundation/Darwin/os，无 AppKit；MLX 官方支持 iOS）
注意：`-skipMacroValidation` 是必需的——mlx-swift-lm 使用 `MLXHuggingFaceMacros`，该宏在 Xcode 工作区 GUI 中需手动授信后才生效；`-skipMacroValidation` 是 xcodebuild CLI/CI 环境下绕过此交互门的官方方式，不影响构建产物安全性（宏本身已由 SPM 校验 checksum）。
若个别文件报 macOS-only API：用 `#if os(macOS)` 包住该 API 并保持 iOS 路径可用，不要整文件排除。

- [ ] **Step 6: Commit**

```bash
git add Package.swift Tests/GemmaTransKitTests/EngineTuningTests.swift
git commit -m "feat: Package 声明 iOS 平台 + 锁定 8GB 设备 E2B 档位契约"
```

---

### Task 2: AppSettings 支持注入 suite（App Group 共享设置）

**Files:**
- Modify: `Sources/GemmaTransKit/AppSettings.swift:39-61`
- Create: `Tests/GemmaTransKitTests/AppSettingsTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `Tests/GemmaTransKitTests/AppSettingsTests.swift`：

```swift
import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct AppSettingsTests {
    /// iOS 上主 app 与扩展经 App Group suite 共享设置；suite 必须可注入
    @Test func roundTripsThroughCustomSuite() {
        let suite = "test.gemmatrans.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var s = AppSettings()
        s.targetDefault = "ja"
        s.manualMaxTokens = 512
        s.save(suiteName: suite)

        let loaded = AppSettings.load(suiteName: suite)
        #expect(loaded.targetDefault == "ja")
        #expect(loaded.manualMaxTokens == 512)
    }

    /// 兼容回归：无参调用仍走 macOS 既有 suite
    @Test func defaultSuiteNameUnchanged() {
        #expect(AppSettings.suiteName == "com.gemmatrans.app")
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift test --filter AppSettingsTests`
Expected: 编译错误 `extra argument 'suiteName' in call`（API 尚不存在）

- [ ] **Step 3: 实现——给 load/save 加默认参数（macOS 调用点零改动）**

`Sources/GemmaTransKit/AppSettings.swift` 中两个方法签名改为：

```swift
    /// 从 UserDefaults 读取（缺省值兜底）。iOS 传 App Group suite 实现主 app/扩展共享。
    public static func load(suiteName: String = Self.suiteName) -> AppSettings {
        guard let d = UserDefaults(suiteName: suiteName) else { return AppSettings() }
        // …方法体不变…
    }

    public func save(suiteName: String = Self.suiteName) {
        guard let d = UserDefaults(suiteName: suiteName) else { return }
        // …方法体不变…
    }
```

（只改签名行与 guard 行的变量名，方法体其余不动。）

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter AppSettingsTests`
Expected: 2 个用例 PASS

- [ ] **Step 5: 全量回归 + Commit**

```bash
swift test
git add Sources/GemmaTransKit/AppSettings.swift Tests/GemmaTransKitTests/AppSettingsTests.swift
git commit -m "feat: AppSettings 支持注入 UserDefaults suite（iOS App Group 共享）"
```

---

### Task 3: TranslationEngine 支持自定义模型缓存目录

**Files:**
- Modify: `Sources/GemmaTransKit/TranslationEngine.swift:29-62`

说明：此改动的行为验证依赖 1.4GB 模型下载，单测不可行；本任务以「macOS 构建+测试全绿 + iOS 交叉编译通过」为完成标准，端到端行为由 Task 5 真机 spike 验证。

- [ ] **Step 1: 修改 load() 签名与加载分支**

`TranslationEngine.swift` 的 `load` 方法改为（预热段及其注释原样保留）：

```swift
    /// 加载模型（首次自动从 HuggingFace 下载，progress 回调驱动 UI 显示百分比）
    /// - Parameter cacheDirectory: 模型缓存目录；nil 用 HubCache 默认位置（macOS 现状）。
    ///   iOS 传 App Group 容器目录，使主 app 与翻译扩展共享同一份模型文件。
    public func load(
        cacheDirectory: URL? = nil,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        // …tuning 推导段原样不动…

        let configuration =
            switch tuning.variant {
            case .gemma4E4B4bit: LLMRegistry.gemma4_e4b_it_4bit
            case .gemma4E2B4bit: LLMRegistry.gemma4_e2b_it_4bit
            }
        let loaded: ModelContainer
        if let cacheDirectory {
            let hub = HubClient(cache: HubCache(cacheDirectory: cacheDirectory))
            loaded = try await loadModelContainer(
                from: #hubDownloader(hub),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            ) { p in
                progress(p.fractionCompleted)
            }
        } else {
            loaded = try await #huggingFaceLoadModelContainer(configuration: configuration) { p in
                progress(p.fractionCompleted)
            }
        }
        // 预热：首次生成触发 Metal 内核编译（冷启可超 30s，曾致首单超时 500）。
        // 在置 ready 前用 1-token 生成把编译做完，用户首单即快。
        let warmup = ChatSession(loaded, generateParameters: GenerateParameters(maxTokens: 1))
        _ = try? await warmup.respond(to: "hi")
        model = loaded
        GTLog.info("mlx model loaded+warmed: \(configuration.name)")
    }
```

（imports 无需新增：MLXLMCommon/MLXHuggingFace/HuggingFace 文件头已有。）

- [ ] **Step 2: 构建与回归**

Run: `swift build && swift test`
Expected: 全绿（默认参数 nil，macOS 行为不变）

- [ ] **Step 3: iOS 交叉编译复查**

Run: `xcodebuild -scheme GemmaTransKit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -skipMacroValidation build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/GemmaTransKit/TranslationEngine.swift
git commit -m "feat: 引擎支持自定义模型缓存目录（iOS App Group 共享模型）"
```

---

### Task 4: AppiOS 工程脚手架（app + 翻译扩展，含 spike 探针）

**Files:**
- Create: `AppiOS/project.yml`
- Create: `AppiOS/Shared/ModelStore.swift`
- Create: `AppiOS/Shared/EngineHolder.swift`
- Create: `AppiOS/GemmaTransiOS/GemmaTransiOSApp.swift`
- Create: `AppiOS/GemmaTransiOS/ContentView.swift`
- Create: `AppiOS/TranslationProvider/TranslationProviderExtension.swift`
- Modify: `.gitignore`（追加 `AppiOS/build/`）

- [ ] **Step 1: 写 project.yml**

`AppiOS/project.yml`：

```yaml
name: GemmaTransiOS
options:
  bundleIdPrefix: com.gemmatrans
  deploymentTarget:
    iOS: "18.4"
packages:
  GemmaTransCore:
    path: ../
settings:
  base:
    DEVELOPMENT_TEAM: G2XC9VU88M
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  GemmaTransiOS:
    type: application
    platform: iOS
    sources: [GemmaTransiOS, Shared]
    info:
      path: GemmaTransiOS/Info.plist
      properties:
        CFBundleDisplayName: GemmaTrans
        CFBundleShortVersionString: "1.0"      # ITMS-90189 教训：版本字段必须显式写进静态 plist
        CFBundleVersion: "1"
        LSApplicationCategoryType: public.app-category.productivity
        UIRequiredDeviceCapabilities: [iphone-performance-gaming-tier]
        UILaunchScreen: {}
        ITSAppUsesNonExemptEncryption: false
    entitlements:
      path: GemmaTransiOS.entitlements
      properties:
        com.apple.security.application-groups: [group.com.gemmatrans]
        com.apple.developer.kernel.increased-memory-limit: true
        com.apple.developer.translation-app: true
    dependencies:
      - package: GemmaTransCore
        product: GemmaTransKit
      - target: TranslationProvider
        embed: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.gemmatrans.GemmaTrans
        PRODUCT_NAME: GemmaTrans
        TARGETED_DEVICE_FAMILY: "1,2"
  TranslationProvider:
    type: extensionkit-extension
    platform: iOS
    sources: [TranslationProvider, Shared]
    info:
      path: TranslationProvider/Info.plist
      properties:
        CFBundleDisplayName: GemmaTrans 翻译
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        EXAppExtensionAttributes:
          EXExtensionPointIdentifier: com.apple.public.translation-ui-provider
    entitlements:
      path: TranslationProvider.entitlements
      properties:
        com.apple.security.application-groups: [group.com.gemmatrans]
        com.apple.developer.kernel.increased-memory-limit: true
    dependencies:
      - package: GemmaTransCore
        product: GemmaTransKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.gemmatrans.GemmaTrans.TranslationProvider
```

注意：`com.apple.developer.translation-app` 按 Apple 文档挂在**主 app**；若 Task 5 自动签名报该 entitlement 错误，先去 developer.apple.com 给 App ID 开 "Default Translation App" capability，仍不行再试挂到扩展 target。

- [ ] **Step 2: 写 ModelStore（两进程共享的存储约定）**

`AppiOS/Shared/ModelStore.swift`：

```swift
import Foundation

/// 主 app 与翻译扩展共享的存储约定（App Group）
enum ModelStore {
    static let appGroupID = "group.com.gemmatrans"
    /// 共享 UserDefaults suite（设置同步）
    static let settingsSuite = appGroupID

    /// 模型缓存目录（传给引擎 cacheDirectory），两进程同读
    static var cacheDirectory: URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) 未配置")  // entitlements 缺失属构建配置错误，fail fast
        }
        return container.appendingPathComponent("models", isDirectory: true)
    }

    /// 模型是否已下载完成。目录布局由 swift-huggingface HubCache 决定：
    /// <cacheDirectory>/models--mlx-community--gemma-4-e2b-it-4bit/
    /// 扩展据此决定「直接加载」还是提示「先打开主 app 下载」——扩展内绝不触发 1.4GB 下载。
    static var modelDownloaded: Bool {
        let dir = cacheDirectory.appendingPathComponent("models--mlx-community--gemma-4-e2b-it-4bit")
        return FileManager.default.fileExists(atPath: dir.path)
    }
}
```

- [ ] **Step 3: 写 EngineHolder（进程级引擎单例，app 与扩展共用源码）**

`AppiOS/Shared/EngineHolder.swift`：

```swift
import Foundation
import Observation
import GemmaTransKit

/// 进程级引擎单例：主 app 与扩展进程各自持有一份（进程隔离互不可见）。
/// 扩展进程存活期间复用热引擎——连续取词免冷载。
@MainActor @Observable
final class EngineHolder {
    enum Status: Equatable {
        case idle
        case downloading(Int)   // 百分比
        case loading            // 权重进显存 + 1-token 预热
        case ready
        case failed(String)
    }

    static let shared = EngineHolder()

    private(set) var status: Status = .idle
    private(set) var engine: TranslationEngine?
    private var loadTask: Task<Void, Never>?

    /// 幂等：并发/重复调用只触发一次加载；失败后可再调重试
    func ensureLoaded() {
        guard loadTask == nil else { return }
        status = ModelStore.modelDownloaded ? .loading : .downloading(0)
        let settings = AppSettings.load(suiteName: ModelStore.settingsSuite)
        let engine = TranslationEngine(settings: settings)
        loadTask = Task {
            do {
                try await engine.load(cacheDirectory: ModelStore.cacheDirectory) { fraction in
                    Task { @MainActor in
                        let pct = Int(fraction * 100)
                        EngineHolder.shared.status = pct < 100 ? .downloading(pct) : .loading
                    }
                }
                self.engine = engine
                self.status = .ready
                GTLog.info("iOS engine ready")
            } catch {
                self.status = .failed("\(error)")
                self.loadTask = nil
                GTLog.error("iOS engine load failed: \(error)")
            }
        }
    }
}
```

- [ ] **Step 4: 写主 app 入口与首版界面（Spike A 可用版）**

`AppiOS/GemmaTransiOS/GemmaTransiOSApp.swift`：

```swift
import SwiftUI

@main
struct GemmaTransiOSApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`AppiOS/GemmaTransiOS/ContentView.swift`：

```swift
import SwiftUI
import GemmaTransKit

struct ContentView: View {
    @State private var holder = EngineHolder.shared
    @State private var input = ""
    @State private var output = ""
    @State private var translating = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader
                TextField("输入或粘贴要翻译的文本", text: $input, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("粘贴") {
                        if let s = UIPasteboard.general.string { input = s }
                    }
                    .buttonStyle(.bordered)
                    Button("翻译") { translate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(holder.status != .ready || translating || input.isEmpty)
                }
                ScrollView {
                    Text(output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("GemmaTrans")
        }
        .task { holder.ensureLoaded() }
    }

    @ViewBuilder private var statusHeader: some View {
        switch holder.status {
        case .idle, .loading:
            Label("正在加载模型…", systemImage: "hourglass")
        case .downloading(let pct):
            ProgressView(value: Double(pct), total: 100) { Text("下载模型 \(pct)%") }
        case .ready:
            Label("引擎就绪（本地 Gemma）", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon").foregroundStyle(.red)
        }
    }

    private func translate() {
        guard let engine = holder.engine else { return }
        translating = true
        output = ""
        let text = input
        Task {
            do {
                let result = try await engine.translate(text, target: nil)
                for try await chunk in result.chunks { output += chunk }
            } catch {
                output = "翻译失败：\(error)"
            }
            translating = false
        }
    }
}
```

- [ ] **Step 5: 写扩展入口（spike 探针版，Task 7 替换为正式面板）**

`AppiOS/TranslationProvider/TranslationProviderExtension.swift`：

```swift
import SwiftUI
import ExtensionKit
import TranslationUIProvider
import GemmaTransKit
import os

@main
final class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            SpikePanelView(context: context)
        }
    }
}

/// Spike 探针面板：上屏即报扩展进程内存额度，再尝试加载引擎翻译选中文字。
/// 测得的数字回写 spec（Task 6）后由正式面板替换（Task 7）。
struct SpikePanelView: View {
    @State var context: any TranslationUIProviderContext
    @State private var lines: [String] = []
    @State private var output = ""

    init(context: any TranslationUIProviderContext) {
        self.context = context
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { Text($0).font(.footnote.monospaced()) }
            if !output.isEmpty { Text(output) }
        }
        .padding()
        .task { await spike() }
    }

    private func spike() async {
        log("内存额度: \(os_proc_available_memory() / 1_048_576) MB")
        guard ModelStore.modelDownloaded else {
            log("模型未下载——请先打开 GemmaTrans 主 app")
            return
        }
        let t0 = Date()
        EngineHolder.shared.ensureLoaded()
        while EngineHolder.shared.status != .ready {
            if case .failed(let msg) = EngineHolder.shared.status {
                log("引擎加载失败: \(msg)")
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        log("引擎就绪: \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        guard let engine = EngineHolder.shared.engine,
              let text = context.inputText.map({ String($0.characters) }),
              !text.isEmpty else { return }
        do {
            let t1 = Date()
            let result = try await engine.translate(text, target: nil)
            var first = true
            for try await chunk in result.chunks {
                if first {
                    log("首字: \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
                    first = false
                }
                output += chunk
            }
            log("完成: \(String(format: "%.1f", Date().timeIntervalSince(t1)))s | " +
                "剩余额度: \(os_proc_available_memory() / 1_048_576) MB")
        } catch {
            log("翻译失败: \(error)")
        }
    }

    private func log(_ s: String) {
        lines.append(s)
        GTLog.info("[spike] \(s)")
    }
}
```

- [ ] **Step 6: .gitignore 追加构建目录**

`.gitignore` 末尾追加一行：

```
AppiOS/build/
```

- [ ] **Step 7: 生成工程并做无签名编译检查**

```bash
cd AppiOS && xcodegen generate
xcodebuild -project GemmaTransiOS.xcodeproj -scheme GemmaTransiOS -skipMacroValidation \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`
常见失败处理：xcodegen 报不认识 `extensionkit-extension` → `brew upgrade xcodegen`（需 ≥2.33）；Swift 6 并发报错按报错点修，不要降 SWIFT_VERSION。

- [ ] **Step 8: Commit**

```bash
cd .. && git add AppiOS .gitignore
git commit -m "feat: AppiOS 脚手架——主 app + TranslationUIProvider 扩展（spike 探针版）"
```

---

### Task 5: Spike A——真机主 app 验证（需用户 iPhone 配合）

**Files:** 无新文件；产出是测量数据与签名验证结论。

前置：用户 iPhone（A17 Pro+，iOS 18.4+）连接本机并信任、开启开发者模式、Wi-Fi 可下载 1.4GB。**到达本任务时先停下请用户接上手机。**

- [ ] **Step 1: 找到设备并带签名构建**

```bash
xcrun devicectl list devices   # 取 <UDID>
cd AppiOS
xcodebuild -project GemmaTransiOS.xcodeproj -scheme GemmaTransiOS -skipMacroValidation \
  -destination "platform=iOS,id=<UDID>" -derivedDataPath build \
  -allowProvisioningUpdates build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`
若报 `com.apple.developer.translation-app` 相关 provisioning 错误：登录 developer.apple.com → Identifiers → com.gemmatrans.GemmaTrans → 勾选 "Default Translation App" capability → 重跑。capability 列表里没有此项 = entitlement 需要特批，**停下来与用户商议**（这是方案 A 的硬门槛）。

- [ ] **Step 2: 安装并启动**

```bash
xcrun devicectl device install app --device <UDID> \
  build/Build/Products/Debug-iphoneos/GemmaTrans.app
xcrun devicectl device process launch --device <UDID> com.gemmatrans.GemmaTrans
```

- [ ] **Step 3: 请用户在手机上操作并回报**

1. 看下载进度条走完（记录大致耗时）
2. 输入框输入 `Good morning, how are you?` → 点「翻译」
3. 回报：是否流式出中文译文；从点击到首字大约几秒

Expected: 译文正常流出。MLX GPU 在 iOS 前台 app 可用是官方支持路径，此步主要验证我们的链路（App Group 目录下载 + E2B 档位 + 预热）。

- [ ] **Step 4: 记录数据（暂存，与 Task 6 一起回写 spec）**

记录：模型下载耗时 / 冷载+预热耗时 / 首字时延 / 全文耗时。

---

### Task 6: Spike B——真机扩展验证 + 决策门 + 回写 spec

**Files:**
- Modify: `docs/superpowers/specs/2026-06-11-ios-app-design.md`（追加 Spike 结果节）

- [ ] **Step 1: 设为默认翻译 App**

请用户：设置 → App → 默认 App → 翻译 → 选 GemmaTrans。
GemmaTrans 没出现在列表里 = entitlement/扩展声明有问题：先核对扩展 Info.plist 的 `EXExtensionPointIdentifier`，再试把 `com.apple.developer.translation-app` 同时挂到扩展 target（改 project.yml 重新生成构建安装）。

- [ ] **Step 2: 真机取词测试（核心测量）**

请用户在备忘录输入一段英文（>50 词），选中 → 菜单「翻译」→ 读 spike 面板输出并截图回报：

- `内存额度: N MB` ← **决定性数字**
- `引擎就绪: Ns` / `首字: Ns` / `完成: Ns | 剩余额度: N MB`
- 紧接着第二次选中取词：`引擎就绪` 是否≈0s（扩展进程是否保活复用）

- [ ] **Step 3: 决策门**

| 结果 | 决策 |
|---|---|
| 翻译成功，热路径首字 < 5s | **GO**：继续 Task 7 |
| 内存额度 < 2500 MB 或加载即被杀 | 试 increased-memory-limit 是否生效（额度数字对比）；仍不行 → **NO-GO** |
| GPU 报错（Metal 受限） | 在 SpikePanelView.spike() 开头加 `MLX.Device.setDefault(device: Device(.cpu))`（`import MLX`）重测 CPU 速度；首字 > 10s 即不可用 → **NO-GO** |

NO-GO 路径：把实测数字写进 spec，状态改回「回退快捷指令方案」，**停止本计划**，回到 brainstorm 重新立项（回退方案见 spec git 历史初版）。

- [ ] **Step 4: 回写 spec 并提交**

在 spec 的 Spike 节末尾追加（实测数字替换占位）：

```markdown
### Spike 结果（2026-06-XX 真机 iPhone XX / iOS XX）

- 扩展进程内存额度：XXXX MB（increased-memory-limit 生效/未生效）
- 扩展内 E2B 冷载+预热：X.Xs；首字：X.Xs；完成：X.Xs；推理后剩余额度：XXXX MB
- 二次取词热进程复用：是/否（就绪 X.Xs）
- 主 app 内：下载 XXs / 冷载 X.Xs / 首字 X.Xs
- 结论：GO 方案 A（扩展内直跑）/ NO-GO 转回退
```

```bash
git add docs/superpowers/specs/2026-06-11-ios-app-design.md
git commit -m "docs: iOS spike 真机结果回写——扩展内本地推理可行性结论"
```

---

### Task 7: 正式翻译面板（替换 spike 探针）

**Files:**
- Create: `AppiOS/TranslationProvider/TranslationPanelView.swift`
- Modify: `AppiOS/TranslationProvider/TranslationProviderExtension.swift`（场景指向新面板，删除 SpikePanelView）

- [ ] **Step 1: 写正式面板**

`AppiOS/TranslationProvider/TranslationPanelView.swift`：

```swift
import SwiftUI
import TranslationUIProvider
import GemmaTransKit

/// 系统「翻译」面板：自动开始翻译，流式输出，拷贝/替换/重试。
struct TranslationPanelView: View {
    @State var context: any TranslationUIProviderContext
    @State private var holder = EngineHolder.shared
    @State private var output = ""
    @State private var header = ""          // 如 "EN → 中文"
    @State private var truncated = false
    @State private var failed: String?
    @State private var done = false
    @State private var expanded = false
    /// nil=自动判向；"zh-Hans"/"en"=强制目标
    @State private var forcedTarget: String?

    init(context: any TranslationUIProviderContext) {
        self.context = context
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topBar
            content
            bottomBar
        }
        .padding()
        .task(id: forcedTarget) { await run() }
    }

    @ViewBuilder private var topBar: some View {
        HStack {
            if !header.isEmpty {
                Text(header).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("目标", selection: $forcedTarget) {
                Text("自动").tag(String?.none)
                Text("中文").tag(String?.some("zh-Hans"))
                Text("EN").tag(String?.some("en"))
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    @ViewBuilder private var content: some View {
        if let failed {
            Label(failed, systemImage: "xmark.octagon").foregroundStyle(.red)
            Button("重试") { Task { await run() } }.buttonStyle(.bordered)
        } else if !ModelStore.modelDownloaded {
            Label("请先打开 GemmaTrans 完成模型下载", systemImage: "arrow.down.circle")
        } else if output.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text(holder.status == .ready ? "翻译中…" : "加载本地模型…")
                    .foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                Text(output)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if truncated {
                Text("文本过长，已翻译前 700 字").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        HStack {
            Button {
                UIPasteboard.general.string = output
            } label: {
                Label("拷贝", systemImage: "doc.on.doc")
            }
            .disabled(output.isEmpty)
            Spacer()
            Button("替换原文") {
                context.finish(translation: AttributedString(output))
            }
            .buttonStyle(.borderedProminent)
            .disabled(!done || output.isEmpty || !context.allowsReplacement)
        }
    }

    private func run() async {
        guard ModelStore.modelDownloaded else { return }
        output = ""; failed = nil; done = false
        EngineHolder.shared.ensureLoaded()
        while holder.status != .ready {
            if Task.isCancelled { return }  // 面板收起 .task 被取消，否则 sleep 抛 CancellationError 被吞、循环变热自旋
            if case .failed(let msg) = holder.status {
                failed = "引擎加载失败：\(msg)"
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let engine = holder.engine,
              let text = context.inputText.map({ String($0.characters) }),
              !text.isEmpty else { return }
        do {
            let result = try await engine.translate(text, target: forcedTarget)
            header = "\(label(result.detected)) → \(label(result.target))"
            truncated = result.truncated
            for try await chunk in result.chunks {
                output += chunk
                if !expanded && output.count > 200 {
                    context.expandSheet()
                    expanded = true
                }
            }
            done = true
        } catch {
            failed = "翻译失败：\(error.localizedDescription)"
            GTLog.error("panel translate failed: \(error)")
        }
    }

    private func label(_ code: String) -> String {
        switch code {
        case "zh-Hans", "zh": return "中文"
        case "en": return "EN"
        default: return code.uppercased()
        }
    }
}
```

- [ ] **Step 2: 扩展入口指向正式面板**

`TranslationProviderExtension.swift` 整文件替换为：

```swift
import SwiftUI
import ExtensionKit
import TranslationUIProvider

@main
final class TranslationProviderExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationPanelView(context: context)
        }
    }
}
```

- [ ] **Step 3: 构建检查**

```bash
cd AppiOS && xcodegen generate
xcodebuild -project GemmaTransiOS.xcodeproj -scheme GemmaTransiOS -skipMacroValidation \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 真机验收清单（请用户操作）**

重新安装到设备（Task 5 Step 1-2 命令），用户逐项确认：
1. 备忘录选英文 → 翻译 → 自动开始流式中文输出，头部显示 `EN → 中文`
2. 长文本（>200 字输出）面板自动加高
3. 「拷贝」后可粘贴出译文
4. 在备忘录（可编辑）「替换原文」可用且替换成功；在 Safari（只读）该按钮置灰
5. 分段控件切到 `EN` → 重新翻译为英文
6. 关掉面板马上再取词 → 第二次明显更快（热进程）

- [ ] **Step 5: Commit**

```bash
cd .. && git add AppiOS/TranslationProvider
git commit -m "feat: 正式翻译面板——流式输出/拷贝/替换原文/目标切换/自动加高"
```

---

### Task 8: 主 app 正式 UI（引导卡 + 设置）

**Files:**
- Modify: `AppiOS/GemmaTransiOS/ContentView.swift`

- [ ] **Step 1: 加引导卡与目标语言设置**

`ContentView.swift` 在 `statusHeader` 之后、`TextField` 之前插入引导卡，并在 NavigationStack 加 toolbar 设置入口。完整改后文件：

```swift
import SwiftUI
import GemmaTransKit

struct ContentView: View {
    @State private var holder = EngineHolder.shared
    @State private var input = ""
    @State private var output = ""
    @State private var translating = false
    @State private var showSettings = false
    @AppStorage("guideDismissed", store: UserDefaults(suiteName: ModelStore.settingsSuite))
    private var guideDismissed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader
                if !guideDismissed && holder.status == .ready { guideCard }
                TextField("输入或粘贴要翻译的文本", text: $input, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("粘贴") {
                        if let s = UIPasteboard.general.string { input = s }
                    }
                    .buttonStyle(.bordered)
                    Button("翻译") { translate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(holder.status != .ready || translating || input.isEmpty)
                }
                ScrollView {
                    Text(output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("GemmaTrans")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
        }
        .task { holder.ensureLoaded() }
    }

    /// 核心引导：设为系统翻译 App 后，任意 app 选中文字即可用 GemmaTrans
    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("开启划词翻译", systemImage: "wand.and.stars").font(.headline)
            Text("设置 → App → 默认 App → 翻译，选择 GemmaTrans。\n之后在任意 app 选中文字点「翻译」，即可离线使用本地 Gemma。")
                .font(.subheadline)
            HStack {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("知道了") { guideDismissed = true }
                    .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var statusHeader: some View {
        switch holder.status {
        case .idle, .loading:
            Label("正在加载模型…", systemImage: "hourglass")
        case .downloading(let pct):
            ProgressView(value: Double(pct), total: 100) { Text("下载模型 \(pct)%（约 1.4GB，建议 Wi-Fi）") }
        case .ready:
            Label("引擎就绪（本地 Gemma）", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon").foregroundStyle(.red)
        }
    }

    private func translate() {
        guard let engine = holder.engine else { return }
        translating = true
        output = ""
        let text = input
        Task {
            do {
                let result = try await engine.translate(text, target: nil)
                for try await chunk in result.chunks { output += chunk }
            } catch {
                output = "翻译失败：\(error)"
            }
            translating = false
        }
    }
}

/// 设置页：目标语言（写入 App Group suite，扩展即时共享）
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.load(suiteName: ModelStore.settingsSuite)

    var body: some View {
        NavigationStack {
            Form {
                Section("目标语言") {
                    Picker("中文译为", selection: $settings.targetForChinese) {
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                    }
                    Picker("其他语言译为", selection: $settings.targetDefault) {
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                    }
                }
                Section {
                    Text("翻译全程在本机完成，不联网、不收集任何数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                Button("完成") {
                    settings.save(suiteName: ModelStore.settingsSuite)
                    dismiss()
                }
            }
        }
    }
}
```

- [ ] **Step 2: 构建检查**

```bash
cd AppiOS && xcodegen generate
xcodebuild -project GemmaTransiOS.xcodeproj -scheme GemmaTransiOS -skipMacroValidation \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 真机验收（请用户操作）**

1. 引导卡可见，「打开设置」跳转系统设置
2. 设置页改「其他语言译为 → English」后，扩展取中文词 → 译为英文（验证 App Group 设置共享）
3. 「知道了」后引导卡消失，重启 app 不再出现

- [ ] **Step 4: Commit**

```bash
cd .. && git add AppiOS/GemmaTransiOS
git commit -m "feat: iOS 主 app 正式 UI——默认翻译 App 引导卡 + 目标语言设置"
```

---

### Task 9: 发布准备（图标 + ASC iOS 平台）

**Files:**
- Create: `AppiOS/GemmaTransiOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `AppiOS/GemmaTransiOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png`（从 macOS icns 提取）
- Modify: `AppiOS/project.yml`（app target settings 加 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`）

- [ ] **Step 1: 从 macOS 图标提取 1024px**

```bash
iconutil -c iconset App/GemmaTrans/AppIcon.icns -o /tmp/AppIcon.iconset
mkdir -p AppiOS/GemmaTransiOS/Assets.xcassets/AppIcon.appiconset
cp /tmp/AppIcon.iconset/icon_512x512@2x.png \
   AppiOS/GemmaTransiOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

`Contents.json`：

```json
{
  "images": [
    { "filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

`project.yml` 的 GemmaTransiOS target `settings.base` 增加一行：

```yaml
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

- [ ] **Step 2: Archive 并导出**

```bash
cd AppiOS && xcodegen generate
xcodebuild -project GemmaTransiOS.xcodeproj -scheme GemmaTransiOS -skipMacroValidation \
  -destination 'generic/platform=iOS' -archivePath build/GemmaTransiOS.xcarchive \
  -allowProvisioningUpdates archive 2>&1 | tail -3
cat > /tmp/export-ios.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>G2XC9VU88M</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath build/GemmaTransiOS.xcarchive \
  -exportOptionsPath /tmp/export-ios.plist -exportPath build/export \
  -allowProvisioningUpdates 2>&1 | tail -3
```

Expected: `build/export/GemmaTrans.ipa` 生成

- [ ] **Step 3: ASC 与上传（与用户确认后执行）**

1. ASC 条目 6778876828（同 bundle id）添加 iOS 平台（asc CLI 已配置，或 ASC 网页操作）
2. 上传：`xcrun altool` 已废弃，用 Transporter 或 `asc` CLI 上传 ipa；先发 TestFlight
3. 提审备注说明：模型 1.4GB 首启下载、纯本地推理、设备门槛 A17 Pro+（iphone-performance-gaming-tier 已声明）
4. iOS 截图：主 app + 翻译面板各 1-2 张（6.7" 必传）

- [ ] **Step 4: Commit**

```bash
cd .. && git add AppiOS
git commit -m "chore: iOS 图标与 App Store 导出配置"
```
