# 本地 API 可选化 + 状态解耦设计

日期：2026-06-10
状态：已确认（API 默认开启、可关；引擎与 API 状态解耦）

## 背景

HTTP 服务只为外部进程（PopClip/Bob/curl）服务；划词热键是进程内调用，不依赖端口。
现状问题：端口被无关程序占用时整体状态置 failed，划词被"陪葬"；启动探测不验身份，无关 HTTP 服务会被误认成 GemmaTrans 实例。

## 设计

### AppSettings

新增 `apiEnabled: Bool = true`（UserDefaults 持久化，键 `apiEnabled`，缺省 true）。

### /health 验明正身（GemmaTransServer）

`GET /health` 响应增加 `"service": "gemmatrans"` 字段。现有 healthReturnsReady 测试同步断言该字段。

### EngineController 状态解耦

- `enum EngineStatus { loading, ready, failed(String) }`
- `enum APIStatus { disabled, running(port: UInt16), failed(String) }`
- 启动流程：单实例探测（见下）→ 引擎加载 → `engineStatus = .ready` → 若 `settings.apiEnabled` 再启动 server。
- `setAPIEnabled(_:)`：开 → 启 serverTask、`apiStatus = .running`；关 → `serverTask.cancel()`（FlyingFox `run()` 响应取消）、`apiStatus = .disabled`。即时生效，同时写回 settings。
- server 任务异常退出（如端口被占）→ 仅 `apiStatus = .failed(...)`，引擎与划词不受影响。
- 单实例守卫与 API 开关无关（防双模型加载）：探测 `/health` 且**响应 JSON 的 `service == "gemmatrans"` 才算同类实例**并放弃启动；其他 HTTP 响应视为端口被无关服务占用——继续加载引擎，apiEnabled 时由 server 绑定失败路径自然落入 `apiStatus = .failed("端口被占用")`。

### UI

- MenuBarExtra：两行状态（"引擎：加载中/就绪/失败"、"API：已关闭 / 127.0.0.1:8765 / 失败原因"）+ `Toggle("本地 API")`。
- SettingsView 的 "API" Section 增加同一开关（与菜单联动，均走 `EngineController.setAPIEnabled`）。

### HotkeyCenter

ready 判断改为 `engineStatus == .ready`（与 API 状态无关）。

### 文档

README：PopClip 一节注明"菜单栏开启'本地 API'（默认已开）"；端口被占的表现与处理。

## 测试

- Server：health 含 `service` 字段（改现有测试）。
- App 层手动验收：① 关 API → 划词正常、curl 连接拒绝；② 再开 API → curl 立即可用（不重启）；③ 用 `python3 -m http.server 8765` 占端口后启动 app → 引擎就绪、划词可用、API 显示失败；④ CLI serve 运行时启动 app → 拒绝启动（同类实例）。

## 不做（YAGNI）

Unix socket / XPC / AppleScript 通道；端口自动递增换端口；API 鉴权。
