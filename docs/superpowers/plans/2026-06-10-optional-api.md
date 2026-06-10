# 本地 API 可选化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HTTP API 变为可即时开关（默认开）；引擎/API 状态解耦，端口被占不再影响划词；单实例探测验明正身。

**Architecture:** `/health` 加 `service` 身份字段（Server 层，TDD）；`EngineController` 拆 `engineStatus`/`apiStatus` 两轨状态并提供 `setAPIEnabled` 即时启停；菜单与设置页加开关；`HotkeyCenter` 只看引擎状态。

**Tech Stack:** 现有栈（FlyingFox、SwiftUI MenuBarExtra、@Observable）。

**Spec:** `docs/superpowers/specs/2026-06-10-optional-api-design.md`

---

### Task 1: /health 身份字段 + AppSettings.apiEnabled（TDD）

**Files:**
- Modify: `Sources/GemmaTransServer/APIServer.swift`（health 路由）
- Modify: `Sources/GemmaTransKit/AppSettings.swift`
- Test: `Tests/GemmaTransServerTests/TranslateRouteTests.swift`（healthReturnsReady）

- [ ] **Step 1: 改 healthReturnsReady 测试，断言 service 字段**

在该测试末尾追加：

```swift
#expect(json["service"] as? String == "gemmatrans")
```

- [ ] **Step 2: 跑测确认失败**

Run: `swift test --filter healthReturnsReady`
Expected: FAIL（service 为 nil）

- [ ] **Step 3: 实现——health 路由响应加字段**

`APIServer.registerRoutes()` 中 health 路由改为：

```swift
await server.appendRoute("GET /health") { _ in
    let ready = await t.isReady
    return try .json(
        ["status": ready ? "ready" : "loading", "service": "gemmatrans"],
        statusCode: ready ? .ok : .serviceUnavailable
    )
}
```

- [ ] **Step 4: AppSettings 加 apiEnabled**

属性区（autoTuning 旁）加 `public var apiEnabled: Bool`；init 参数追加 `apiEnabled: Bool = true` 并赋值；load() 追加：

```swift
if d.object(forKey: "apiEnabled") != nil { s.apiEnabled = d.bool(forKey: "apiEnabled") }
```

save() 追加：

```swift
d.set(apiEnabled, forKey: "apiEnabled")
```

- [ ] **Step 5: 跑测 + Commit**

Run: `swift test`
Expected: 全部 PASS

```bash
git add Sources/ Tests/
git commit -m "feat: /health 身份字段 + apiEnabled 设置项"
```

### Task 2: EngineController 状态解耦 + 即时开关

**Files:**
- Modify: `App/GemmaTrans/EngineController.swift`（整文件重写）
- Modify: `App/GemmaTrans/HotkeyCenter.swift`（ready 判断）

- [ ] **Step 1: 重写 EngineController**

```swift
// App/GemmaTrans/EngineController.swift
import Foundation
import Observation
import GemmaTransKit
import GemmaTransServer

@MainActor @Observable
final class EngineController {
    enum EngineStatus: Equatable { case loading, ready, failed(String) }
    enum APIStatus: Equatable { case disabled, running(UInt16), failed(String) }

    static let shared = EngineController()

    private(set) var engineStatus: EngineStatus = .loading
    private(set) var apiStatus: APIStatus = .disabled
    private(set) var engine: TranslationEngine?
    private var serverTask: Task<Void, Error>?
    private(set) var settings = AppSettings.load()

    func start() {
        engineStatus = .loading
        Task {
            // 单实例守卫（验明正身）：仅真正的 GemmaTrans 实例才放弃启动，防双模型加载
            if await Self.isGemmaTransServing(settings.port) {
                engineStatus = .failed("端口 \(settings.port) 已有 GemmaTrans 实例在运行")
                GTLog.error("startup aborted: another GemmaTrans on \(settings.port)")
                return
            }
            let engine = TranslationEngine(settings: settings)
            do {
                try await engine.load()
                self.engine = engine
                engineStatus = .ready
                GTLog.info("engine ready")
                if settings.apiEnabled { startServer() }
            } catch {
                engineStatus = .failed("\(error)")
                GTLog.error("engine load failed: \(error)")
            }
        }
    }

    /// 菜单/设置开关入口：即时生效并持久化
    func setAPIEnabled(_ enabled: Bool) {
        settings.apiEnabled = enabled
        settings.save()
        if enabled {
            if engineStatus == .ready { startServer() }
            // 引擎未就绪时由 start() 的 apiEnabled 分支接管
        } else {
            serverTask?.cancel()
            serverTask = nil
            apiStatus = .disabled
            GTLog.info("API disabled by user")
        }
    }

    private func startServer() {
        guard let engine, serverTask == nil else { return }
        let port = settings.port
        let task: Task<Void, Error> = Task.detached {
            try await APIServer(translator: engine, port: port).run()
        }
        serverTask = task
        apiStatus = .running(port)
        GTLog.info("API serving on \(port)")
        Task {
            do { try await task.value }
            catch is CancellationError { /* 用户关闭，状态已在 setAPIEnabled 置 disabled */ }
            catch {
                // 仅在仍处运行态时标记失败（避免覆盖用户主动关闭后的状态）
                if case .running = self.apiStatus {
                    self.apiStatus = .failed("端口 \(port) 不可用")
                    self.serverTask = nil
                    GTLog.error("API server died: \(error)")
                }
            }
        }
    }

    private static func isGemmaTransServing(_ port: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["service"] as? String == "gemmatrans"
    }
}
```

- [ ] **Step 2: HotkeyCenter 改判引擎状态**

`HotkeyCenter.handle` 中：

```swift
guard controller.engineStatus == .ready, let engine = controller.engine else {
    NSSound.beep()
    return
}
```

（原 `guard case .ready = controller.status` 删除。）

- [ ] **Step 3: 构建确认（UI 未改会编译错，连同 Task 3 一起改完再构建也可）**

Run: `cd App && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error|BUILD"`
Expected: GemmaTransApp.swift 引用旧 `controller.status` 报错 → Task 3 修复（两任务连续执行，一次构建验证）

### Task 3: 菜单/设置开关 + README + 真机验证

**Files:**
- Modify: `App/GemmaTrans/GemmaTransApp.swift`
- Modify: `App/GemmaTrans/SettingsView.swift`
- Modify: `README.md`

- [ ] **Step 1: MenuBarExtra 两行状态 + 开关**

```swift
MenuBarExtra {
    switch controller.engineStatus {
    case .loading: Text("引擎：模型加载中…")
    case .ready: Text("引擎：就绪")
    case .failed(let msg): Text("引擎失败: \(msg)")
    }
    switch controller.apiStatus {
    case .disabled: Text("API：已关闭")
    case .running(let port): Text("API：127.0.0.1:\(String(port))")
    case .failed(let msg): Text("API 失败: \(msg)")
    }
    Divider()
    Toggle("本地 API", isOn: Binding(
        get: { EngineController.shared.settings.apiEnabled },
        set: { EngineController.shared.setAPIEnabled($0) }
    ))
    SettingsLink { Text("设置…") }
    Button("退出") { NSApplication.shared.terminate(nil) }
} label: {
    Image(systemName: controller.engineStatus == .ready ? "character.bubble.fill" : "character.bubble")
}
```

- [ ] **Step 2: SettingsView 的 API Section 加开关，保存防回写陈旧值**

API Section 第一行加：

```swift
Toggle("启用本地 API（PopClip 等外部工具需要）", isOn: Binding(
    get: { EngineController.shared.settings.apiEnabled },
    set: { EngineController.shared.setAPIEnabled($0) }
))
```

保存按钮 action 的 `settings.save()` 之前加一行（防止视图里的陈旧副本覆盖菜单开关）：

```swift
settings.apiEnabled = EngineController.shared.settings.apiEnabled
```

- [ ] **Step 3: 构建 + 重启**

Run: `cd App && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error|BUILD"; pkill -x GemmaTrans; open build/Build/Products/Debug/GemmaTrans.app`
Expected: BUILD SUCCEEDED，菜单显示"引擎：就绪 / API：127.0.0.1:8765"

- [ ] **Step 4: 程序化验证（无 GUI 部分）**

① 默认开：`python3 urllib /health` → `service: gemmatrans`；② 端口被无关服务占用：先 `python3 -m http.server 8765` 再启动 app → 日志 `engine ready` + `API server died`，`/health` 仍是 python 的 404（引擎未被陪葬，apiStatus failed）；④ CLI serve 占用：CLI 起来后启动 app → 日志 `startup aborted`。③（菜单即时开关）留给用户 GUI 验证。

- [ ] **Step 5: README 更新 + Commit**

PopClip 一节第 2 步前加："菜单栏确认'本地 API'开启（默认已开）"；API 文档节加一句："API 可在菜单栏/设置中即时开关；关闭后划词翻译不受影响（进程内调用，不走端口）；端口被其他程序占用时菜单会显示 API 失败、划词照常可用。"

```bash
git add App/ README.md
git commit -m "feat: 本地 API 即时开关 + 引擎/API 状态解耦"
```

---

## 自查

spec 覆盖：service 字段+测试 ✓（T1）、apiEnabled 持久化 ✓（T1）、状态解耦/即时启停/失败不串扰 ✓（T2）、守卫验身份且与开关无关 ✓（T2）、热键只看引擎 ✓（T2）、菜单两行+开关/设置开关/防陈旧回写 ✓（T3）、README ✓（T3）、手动+程序化验收映射 spec 四场景 ✓。类型一致：`setAPIEnabled(_:)`、`engineStatus`/`apiStatus` 名称三处统一。
