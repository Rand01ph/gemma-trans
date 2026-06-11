# GemmaTrans iOS 版设计（v1 立项）

日期：2026-06-11（同日修订：交互调研后主攻方向改为系统「默认翻译 App」入口）
状态：已确认（v1 仅做入口 1 跑通主流程；原快捷指令方案降为回退预案，见 git 历史初版）

## 背景：交互调研结论（2026-06）

iOS 18.4 起开放「默认翻译 App」（TranslationUIProvider 框架，全球可用，非欧盟限定）：
第三方 app 可接管系统编辑菜单的「翻译」按钮——任意 app 选中文字 → 点「翻译」→ 第三方
翻译面板在宿主 app **原地弹出**（系统托管的扩展 UI，XPC 传入 `context.inputText`），并支持
`context.finish(replacingWithTranslation:)` 回写替换选中文字。DeepL / Google 翻译 / 欧路词典 /
Para 翻译均已接入。这是 iOS 上步数最少（选中 → 翻译，2 步）、学习成本为零的划词翻译交互，
定为 v1 唯一跨 app 入口。

调研同时确认：编辑菜单加自定义按钮仍不可能；PiP 剪贴板悬浮窗（Para 模式）活跃且过审但属
逐案放行的灰色地带；快捷指令链路可行但多一步且入口更深。后两者推迟（见"不做"）。

## 目标与交互

用户在任意 iOS app 选中文字 → 编辑菜单「翻译」→ GemmaTrans 面板原地弹出（不离开当前 app）
→ **流式显示本地 Gemma 译文** → 可拷贝；在可编辑文本中可一键「替换原文」。

- 面板：译文为主，自动判向（中↔英），目标语言切换，极简不堆功能
- 首次体验：主 app 引导卡「设为系统翻译 App」，一键跳系统设置（设置 > App > 默认 App > 翻译），
  一次性配置
- 主 app 自身：粘贴/输入翻译（流式）、模型下载（**显式按钮触发**，含国内镜像开关
  hf-mirror.com——真机反馈：国内直连 huggingface.co 卡死；自动下载 1.4GB 太粗暴）、
  设置（目标语言）

## 硬约束与待验证

- TranslationUIProvider：iOS/iPadOS 18.4+；需 `com.apple.developer.translation-app`
  entitlement（是否需向 Apple 申请待查）+ Translation 扩展 target；纯本地推理无需
  network-access 声明（离线即卖点）
- **扩展是独立进程，内存帽未知（spike 头号问题）**：1.4GB Gemma E2B 能否在扩展内加载推理；
  `increased-memory-limit` entitlement 对该扩展类型是否生效
- 扩展无法后台唤醒主 app（iOS 通用限制，初版 spec 已核实）→ "扩展转交主 app 推理"大概率
  不可行，优先验证扩展内直跑
- 扩展进程生命周期不可控 → 连续取词可能每次冷载（E2B 冷载预估 3-4s），需实测是否复用热进程
- 全部不可行 → 回退初版方案：快捷指令分享表单 + App Intent 后台翻译 + 通知保底

## 设备与模型

- 模型：仅 **Gemma 4 E2B-4bit（约 1.4GB）**；EngineTuning 增加 iOS 档（maxTokens 1024 /
  输入 700 字符）
- 设备门槛：`UIRequiredDeviceCapabilities: iphone-performance-gaming-tier`（A17 Pro 及以上
  / M 系 iPad，即 8GB+ RAM 设备）+ `com.apple.developer.kernel.increased-memory-limit`
- 最低系统 **iOS 18.4**（A17 Pro+ 设备全部可升，相比 iOS 17 实际损失为零）

## 架构（最大化复用）

- `Package.swift` platforms 增加 iOS；GemmaTransKit 全量复用（引擎/调优/检测/提示词/GTLog
  均为 Foundation/MLX，无 AppKit 依赖）；GemmaTransServer 不进 iOS
- 新增 `AppiOS/`（XcodeGen `project.yml`，独立于 macOS 的 App/，deployment target 18.4）：
  - `GemmaTransiOSApp.swift`：SwiftUI 单屏（输入框 + 粘贴按钮 + 流式结果 + 下载进度 +
    「设为系统翻译 App」引导卡）
  - `TranslationExtension/`：`TranslationUIProviderExtension` +
    `TranslationUIProviderSelectedTextScene`，SwiftUI 面板（流式文本 + 拷贝/替换按钮）；
    `EngineHolder` 在扩展进程内加载引擎，加载后 1-token 预热（复用 macOS 经验）
  - 模型文件放 **App Group 共享容器**：主 app 下载一次，扩展直接读取
- 发布：在现有 ASC 条目 **6778876828 添加 iOS 平台**（同 bundle id），提审材料复用并增配
  iOS 截图

## Spike（第一任务，需用户 iPhone 连接本机配合）

真机验证：① 翻译扩展进程实际内存帽（有/无 increased-memory-limit entitlement 两种情况）；
② 扩展内 MLX **GPU** 推理可行性、E2B 冷载→首字端到端时延（目标 < 5s）；③ 连续两次取词
是否复用热进程；④ GPU 不可用时 MLX CPU 模式速度；⑤ 全不可行 → 回退快捷指令方案。
结论回写本 spec。

## 不做（YAGNI v1）

PiP 剪贴板悬浮窗（v2 候选，对标 Para；审核逐案放行）；快捷指令 / App Intent 入口及操作
按钮、背面轻点、控制中心等触发器玩法（仅作回退预案）；Share Extension；通知保底（面板
前台呈现，无需通知）；iPad 专属布局；历史记录；iOS 本地 API。
