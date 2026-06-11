# GemmaTrans iOS 版设计（v1 立项）

日期：2026-06-11
状态：已确认（方案 A 主攻 + D 保底；用户无异议按推荐执行）

## 目标与交互

用户在任意 iOS app 选中文字 → 分享菜单 → "GemmaTrans 翻译"快捷指令 → **不离开当前 app**，
系统在后台拉起主 app 进程执行翻译（App Intents `openAppWhenRun = false`）→ 译文以系统结果
弹窗原地显示（方案 A）。若后台路径在真机 spike 中不可行 → 保底为分享跳主 app 流式显示 +
完成时本地通知横幅（方案 D，同一套代码的降级分支）。

主 app 自身提供：粘贴/输入翻译（流式）、模型下载进度、设置（目标语言、通知开关）。

## 硬约束（已核实）

- 分享扩展内存帽约 120MB → 扩展内不可能跑 LLM；v1 不做 Share Extension，分享入口由
  快捷指令的"显示在分享表单"承担（文档引导用户一次性开启）
- 扩展无法后台唤醒主 app；App Intents 后台执行是唯一合规的"无跳转"通道（约 30s 时限）
- **待 spike 验证**：后台 App Intent 进程内 MLX **GPU** 推理是否被 iOS 限制（Metal 后台
  执行受限）；不行则测 MLX CPU 模式速度；两者都不可行 → 全面转方案 D

## 设备与模型

- 模型：仅 **Gemma 4 E2B-4bit（约 1.4GB）**；EngineTuning 增加 iOS 档（maxTokens 1024 /
  输入 700 字符）
- 设备门槛：`UIRequiredDeviceCapabilities: iphone-performance-gaming-tier`（A17 Pro 及以上
  / M 系 iPad，即 8GB+ RAM 设备）+ `com.apple.developer.kernel.increased-memory-limit`
- 最低系统 iOS 17

## 架构（最大化复用）

- `Package.swift` platforms 增加 `.iOS(.v17)`；GemmaTransKit 全量复用（引擎/调优/检测/
  提示词/GTLog 均为 Foundation/MLX，无 AppKit 依赖）；GemmaTransServer 不进 iOS
- 新增 `AppiOS/`（XcodeGen `project.yml`，独立于 macOS 的 App/）：
  - `GemmaTransiOSApp.swift`：SwiftUI 单屏（输入框 + 粘贴按钮 + 流式结果 + 下载进度态）
  - `EngineHolder.swift`：进程级引擎单例（intent 与 UI 共用；后台 intent 命中已加载的
    热引擎时秒出）
  - `TranslateIntent.swift`：AppIntents；`openAppWhenRun=false`；参数 `text: String`
    （支持快捷指令分享表单输入）；执行：引擎热则直接推理，冷则加载（E2B 冷载预估 3-4s）；
    返回 `.result(dialog:)` 原地弹译文；接近时限或失败 → 发本地通知（保底显示）并提示
    打开主 app
  - 通知：`UNUserNotificationCenter` 本地通知（首次请求授权），设置中可关
- 发布：在现有 ASC 条目 **6778876828 添加 iOS 平台**（同 bundle id），提审材料复用并
  增配 iOS 截图

## Spike（第一任务，需用户 iPhone 连接本机配合）

真机验证：① 后台 App Intent 内 MLX GPU 推理可行性；② 冷/热路径端到端时延（目标：热
路径 < 5s 出首字）；③ GPU 不可用时 MLX CPU 模式 E2B 速度。结论回写本 spec，决定 A/D。

## 不做（YAGNI v1）

PiP 悬浮窗保活（审核灰色+复杂）；扩展内系统 Translation framework（非 Gemma）；
Share Extension；iPad 专属布局；历史记录；iOS 本地 API。
