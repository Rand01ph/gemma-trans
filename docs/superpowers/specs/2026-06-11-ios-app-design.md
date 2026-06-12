# GemmaTrans iOS 版设计（v1 立项）

日期：2026-06-11（二次修订：Spike B 实测扩展额度 221MB，扩展内推理 NO-GO；
主交互改为「快捷指令 App Intent 后台翻译 + 系统翻译按钮轻跳板」组合，用户已确认）
状态：执行中

## 当前方向（Spike B 后修订）

- **主路径**：选中 → 分享表单 → 快捷指令 → App Intent（`openAppWhenRun=false`）后台拉起
  **主 app 进程**（额度充足，模型已实测可跑）翻译 → `.result(dialog:)` 原地弹译文
- **辅路径**：系统「翻译」按钮保留——面板改**轻量跳板**（不碰模型）：选中文字预览 +
  「在 GemmaTrans 中翻译」按钮经 URL scheme 跳主 app 直接出流式译文
- **待验证（新 spike）**：① 后台 App Intent 进程内 MLX GPU 推理是否可行、端到端时延
  （30s intent 时限内）；② 翻译面板扩展里 openURL 能否打开主 app
- PiP 复制即译悬浮窗：v2 候选不变

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

## 模型分发（真机 spike 发现的硬约束）

国内网络下 HF 模型下载不可达：`model.safetensors` 被 302 到 Xet CDN
（`cas-bridge.xethub.hf.co`），直连被重置、hf-mirror 镜像透传同样撞墙（2026-06-11
iPhone 真机实测，-1005/-1001）。**v1 上架前必须解决模型托管**——候选：ModelScope /
自托管 CDN / App 内置（超出蜂窝 OTA 限制需 Wi-Fi）。spike 阶段绕行：Mac 经
`gemma-trans-cli download-e2b` 代下，devicectl 推入 App Group 容器。

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

## Spike 结果（2026-06-11 真机 iPhone 17 Pro / iOS 27.0）

- **模型体积修正：E2B-4bit 实为 3.58GB**（spec 原写 1.4GB 是错的；EngineTuning.estimatedBytes
  同样低估一倍以上，遗留问题待修）
- 主 app：ModelScope 国内源下载 3.6GB 成功（断点续传实测生效）；**加载+Metal 预热约 5s**；
  MLX GPU 推理正常
- 默认翻译 App 链路全通：entitlement 自动签名通过（无需特批）、选中→翻译弹出我们的面板
- **扩展进程内存额度实测 221 MB**（增配 entitlement 对扩展无效，app 专属）→ 加载模型即被
  jetsam 击杀 → **方案 A（扩展内直跑）NO-GO，任何本地 LLM 都不可能在扩展内运行**
- 模型分发：HF Xet CDN 国内不可达、hf-mirror 已不代理 Xet 仓库；**ModelScope 为国内源**
  （自研 ModelDownloader 双源+字节级进度已实现并实测）
- **后台 GPU 实测 NO（决定性）**：iPhone 17 Pro / iOS 27.0 探针 `BGTaskScheduler.supportedResources`
  不含 `.gpu`（前台额度 6141MB，够跑模型）。后台 GPU 不是老机型局限——iPhone **全系**关着
  （iOS 26+ 的 BGContinuedProcessing `.gpu` 目前只放 iPad）。结论：MLX(Metal GPU) 在后台/扩展
  必被 revoke 崩溃，**「不切走当前 app 还跑 GPU 推理」在 iPhone 上彻底死路**，提高设备门槛无解。
  唯一剩余的「不跳转」窄路 = 后台 App Intent + **MLX CPU 模式**（CPU 不受后台限制），速度待 spike。
- **后台 App Intent 路径 GO（重大）**：openAppWhenRun=false + intent 在主 app target → 走
  「完整 app 后台无-scene 进程」，**额度实测 6125MB（非扩展级，与 221MB 扩展是两个世界）**。
  CPU 模式短句翻译：加载 3.0s + 推理 0.2s，不崩、远在 ~30s intent 时限内。「原地不跳转」成立。
- **iOS 固定 E2B（内存硬约束，非质量取舍）**：后台/前台额度均 ~6GB；E2B 加载后剩 583MB
  → **实测驻留约 5.4GB**（远超 EngineTuning.estimatedBytes 的 1.5GB 估算）。E4B 驻留 7-8GB
  会 OOM，**iOS 装不下 E4B，只能 E2B**。划词短句场景 E2B 质量够用。macOS 默认仍 E4B。

## 不做（YAGNI v1）

PiP 剪贴板悬浮窗（v2 候选，对标 Para；审核逐案放行）；快捷指令 / App Intent 入口及操作
按钮、背面轻点、控制中心等触发器玩法（仅作回退预案）；Share Extension；通知保底（面板
前台呈现，无需通知）；iPad 专属布局；历史记录；iOS 本地 API。

**云端 fallback（v2 候选，2026-06-12 摸底）**：扩展 221MB 跑不了本地模型，但联网调
OpenRouter（OpenAI 兼容，HTTP 几 KB 不吃内存）可行——**这是让「默认翻译 App + 替换原文」
在 iOS 落地的唯一路径**（扩展直连云端 → `finish(replacingWithTranslation:)` 替换选中原文）。
架构顺：`TranslationService` 已是抽象、`GemmaTransServer` 已 OpenAI 兼容，加 `RemoteTranslator`
即可。障碍：① API key 只能用户自填（内置共享 key 免费额度秒杀+滥用）；② 免费模型限速/易变，
只能兜底不能主力；③ 文本上传第三方，与「完全本地」卖点冲突，须默认关 + 隐私清单披露。
v1 保持纯本地定位，搁置。
