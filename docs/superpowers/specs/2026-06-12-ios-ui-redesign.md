# GemmaTrans iOS UI 重设计方案

日期：2026-06-12
状态：待评审（纯设计文档，不含实现；落地由后续实现代理按第 5 节执行）
前置：[2026-06-11-ios-app-design.md](2026-06-11-ios-app-design.md)（产品定位 + spike 结论：扩展 221MB 内存帽 NO-GO，面板降级为跳转主 app）

## 0. 现状诊断

当前 `ContentView.swift` 是 spike 脚手架直接长出来的：一个 VStack 从上到下怼了状态行、
TextField、两个按钮、ScrollView，所有引擎状态（包括 3.6GB 下载和失败红字）挤在同一个
`statusHeader` 里。问题不是缺功能，是**信息架构错位**：

- 引擎状态永远占据屏幕 C 位——就绪后那行绿色「引擎就绪」对用户毫无价值，却天天在
- 下载 3.6GB 是首次启动的「大事件」，现在被压成一行 ProgressView，失败则是两行红字
- 翻译工作区（产品唯一核心）没有视觉重心：输入框是默认 roundedBorder，译文是裸 Text
- 没有语向感知、没有拷贝按钮、没有空态引导，「设为系统翻译 App」引导尚未落地

重设计原则：**翻译工作区是唯一主角；引擎只在需要用户介入时才出场；下载是仪式不是报错。**

## 1. 设计语言

基调：克制的原生 iOS 26 质感。全部用系统语义色 + 系统材质（Liquid Glass 时代的
materials），不画自定义渐变、不加阴影卡片、不引入任何 web 风格的 hex 硬编码视觉。
深色模式是第一公民（所有 token 双值，验收以暗色截图为准）。

### 1.1 配色 token（Assets.xcassets 定义，命名即代码引用名）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| （系统）`systemGroupedBackground` | #F2F2F7 | #000000 | 主屏画布 |
| （系统）`secondarySystemGroupedBackground` | #FFFFFF | #1C1C1E | 输入卡 / 译文卡底 |
| （系统）`tertiarySystemFill` | — | — | 卡内嵌控件（语向 pill 底、字符计数底） |
| `AccentColor` | #1E8E7E | #5BD6C0 | 唯一品牌色：翻译按钮、进度环、流式光标、链接。暗色亮一档保证对比 |
| （系统）`label` / `secondaryLabel` / `tertiaryLabel` | — | — | 文字三级 |
| （系统）`systemOrange` | — | — | 可恢复警示（下载失败）。**禁用大面积红色**——失败可重试，不是灾难 |

- 品牌色取松石绿系：与 Apple 翻译的蓝、DeepL 的深蓝错开，且「绿=本地/离线/安全」心智成立
- 材质：悬浮元素（加载 pill、引导卡）用 `.thinMaterial`；主操作按钮在 iOS 26+ 走
  `.glassEffect()`（`if #available` 包装，18.4 回退 `.borderedProminent`），卡片不用材质
  （分组背景上的实底卡才是原生设置/翻译 App 的做法）
- 永不出现的东西:自定义阴影、描边卡、渐变按钮、emoji 当图标

### 1.2 字体层级（全部系统字体 SF Pro，跟随动态字体）

| 角色 | 字号 | 备注 |
|---|---|---|
| 译文（短，≤120 字符） | `.title3`(20) regular | 译文是产品输出，给最大视觉权重 |
| 译文（长） | `.body`(17) regular | `lineSpacing(4)`，`textSelection(.enabled)` |
| 输入文字 | `.body`(17) | |
| 语向 / 状态说明 | `.footnote`(13) `secondaryLabel` | |
| 字节进度数字 | `.footnote.monospacedDigit()` | 进度跳动不抖动布局 |
| 首启标题 | `.title2`(22) semibold | 仅 onboarding 用 |
| 导航标题 | inline（不用大标题——单屏工具 app，大标题浪费一行） | |

### 1.3 圆角与间距（4pt 网格）

- 卡片圆角 **20pt** `.continuous`（iOS 26 大圆角语境）；卡内嵌控件 12pt，遵守同心圆角
  （内radius ≈ 外radius − 内边距）；按钮一律 capsule
- 屏幕水平边距 16；卡内 padding 16；卡间距 12；区块间距 24
- 触控目标 ≥ 44pt

### 1.4 图标

仅 SF Symbols，`hierarchical` 渲染、`.medium` 字重。关键符号约定：
翻译触发 `arrow.up`（圆形发送钮，对齐 iMessage 心智）、拷贝 `doc.on.doc`、
粘贴 `doc.on.clipboard`、语向 `arrow.left.arrow.right`、下载 `arrow.down`、
本地隐私 `lock.shield`、设置 `gearshape`、系统翻译引导 `character.bubble`。

### 1.5 动效与触感

- 流式光标：译文末尾 `▍`（accent 色），0.6s 淡入淡出循环；`reduceMotion` 时不闪只常显
- 拷贝成功：`UIImpactFeedbackGenerator(.light)` + 按钮图标 0.8s 内变 `checkmark`
- 下载进度环：`ProgressView` 数值动画默认 spring；状态切换用 `.transition(.opacity)`，
  不做花活

## 2. 主屏信息架构与布局重构

### 2.1 状态路由（ContentView 只做这一件事）

```
holder.status
├─ .idle / .downloading / .failed  →  OnboardingView（全屏接管，首启仪式）
└─ .loading / .ready               →  TranslatorView（工作区；loading 以 pill 叠加呈现）
```

关键转变：**模型未就绪时根本不渲染工作区**。现状是「工作区 + 顶部塞一条下载 UI」，
重设计后未下载 = 全屏 onboarding，下载完成 = onboarding 整体淡出、工作区淡入，
一次性仪式感由此而来。

### 2.2 工作区（TranslatorView）布局

- **导航栏**：inline 标题「GemmaTrans」，右侧 `gearshape` 开设置 sheet。没有任何状态文案
- **语向 pill**（导航栏下方，居左）：`自动 · 中文 ⇄ English ▾`，tertiaryFill 底 capsule。
  点击弹目标语言菜单（即设置里的两项快捷入口）。翻译完成后变为实际语向
  `中文 → English`（来自 `result.detected/target`，已有字段）
- **输入卡**：`TextEditor`（透明底）置于卡内，3~8 行自适应；卡右下角一颗 **44pt 圆形
  accent 发送钮**（`arrow.up`）= 翻译触发；输入为空时该位置显示「粘贴」胶囊按钮
  （空态最高频动作是粘贴，按钮原位替换、零移动成本）。接近 700 字上限时左下角浮出
  `652 / 700` 计数（footnote、超限变 orange）。输入非空时左上角出现 `×` 清除
- **译文卡**：仅在有内容时存在（`.transition(.opacity.combined(with: .move(edge: .bottom)))`）。
  卡内：译文文本（1.2 节字级规则）+ 底部行 = 左侧语向 caption、右侧 `doc.on.doc` 拷贝。
  流式期间拷贝禁用、文末挂光标 `▍`；完成后光标消失、拷贝可用
- **引擎加载 pill**（仅 `.loading` 约 5s）：语向 pill 右侧并排一颗 `.thinMaterial` 胶囊
  `⟳ 正在加载模型`，就绪即淡出。**就绪后无任何常驻状态元素**——「正常」就该是隐形的。
  loading 期间发送钮置灰但输入可编辑（用户可先打字）
- **引导卡**（一次性）：就绪空态时，屏幕底部安全区上方一张 `.thinMaterial` 卡：
  `character.bubble` +「在任何 App 选中文字即可用 GemmaTrans 翻译」+「去设置」/「以后再说」。
  `@AppStorage` 记忆 dismissed，设置过或关闭过永不再现（设置 sheet 里保留入口）
- 键盘：`.scrollDismissesKeyboard(.interactively)`；整体套 ScrollView 防小屏键盘顶死

## 3. 关键状态线框

### 3.1 首启未下载（OnboardingView · idle）

```
┌─────────────────────────────┐
│                             │
│        ╭─────────╮          │
│        │ lock.   │          │   64pt hierarchical 符号，accent
│        │ shield  │          │
│        ╰─────────╯          │
│                             │
│     完全离线的本地翻译        │   .title2 semibold
│  Gemma 模型在你的 iPhone 上   │   .subheadline secondaryLabel
│  运行，文本永远不离开设备。     │   （隐私卖点放在下载理由之前）
│                             │
│  ┌───────────────────────┐  │
│  │ 模型大小      3.6 GB  │  │   实底卡（圆角20）内两行 List 风格
│  │ 使用国内源    (○──)   │  │   Toggle + footnote「国内网络建议开启」
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │   ↓  下载模型          │  │   全宽 capsule accent（iOS26 glass）
│  └───────────────────────┘  │
│   建议在 Wi-Fi 环境下载        │   .footnote tertiaryLabel 居中
└─────────────────────────────┘
```

要点：这是「欢迎页」不是「错误页」。隐私价值先行，让 3.6GB 显得值得；
国内源开关从工作区顶部移进这张卡（它只在下载前有意义）。

### 3.2 下载中（OnboardingView · downloading）

```
┌─────────────────────────────┐
│                             │
│         ◠◠◠◠◠               │
│       ◠   42%   ◠           │   120pt 环形进度（accent，圆头线帽）
│       ◡  1.5 GB  ◡          │   中心：百分比 .title2 monospacedDigit
│         ◡◡◡◡◡    /3.6 GB    │   字节行 .footnote monospacedDigit
│                             │
│      正在下载翻译模型          │   .headline
│   请保持 GemmaTrans 在前台    │   .footnote secondaryLabel
│   （已为你暂停自动锁屏）        │   ← isIdleTimerDisabled 的明示
│                             │
│   支持断点续传，中断后可继续     │   .footnote tertiaryLabel
└─────────────────────────────┘
```

要点：环形进度 = 仪式感主视觉；字节级进度是自研下载器的肌肉，给等宽数字让它体面地跳。
HF 宏路径字节为 nil 时中心只显示百分比、字节行隐藏（已有 `downloadLabel` 同款逻辑）。

### 3.3 下载失败 + 重试（OnboardingView · failed）

```
┌─────────────────────────────┐
│                             │
│        wifi.exclamation     │   48pt，systemOrange（不是红）
│                             │
│       下载中断了              │   .title3 semibold
│   网络连接不稳定，已下载的      │   engineLoadFailureMessage 短句
│   部分已保留，可继续下载。      │   + 固定一句「已保留进度」兜底安抚
│                             │
│  ┌───────────────────────┐  │
│  │      继续下载           │  │   主按钮（文案不是「重试」——
│  └───────────────────────┘  │    断点续传让它名副其实）
│                             │
│   使用国内源（ModelScope）(○─)│   失败态把源开关再次亮出——
│                             │   最常见自救路径就是切源
└─────────────────────────────┘
```

要点：橙色、人话、强调「进度已保留」，把红字报错变成「歇了口气，继续」。

### 3.4 就绪空态（TranslatorView · ready，无输入无译文）

```
┌─────────────────────────────┐
│ GemmaTrans              ⚙   │
│ (自动 · 中文 ⇄ English ▾)    │
│ ┌─────────────────────────┐ │
│ │ 输入或粘贴要翻译的文本     │ │   placeholder tertiaryLabel
│ │                         │ │
│ │                 (粘贴 ⧉) │ │   输入为空→右下角是「粘贴」胶囊
│ └─────────────────────────┘ │
│                             │
│        （留白）              │   不放插画不放 slogan——
│                             │   键盘一弹起这里就是键盘
│ ┌─────────────────────────┐ │
│ │ 💬 在任何 App 选中文字即可 │ │   引导卡 .thinMaterial（一次性）
│ │    用 GemmaTrans 翻译     │ │
│ │        [去设置] [以后再说] │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

### 3.5 流式输出中

```
┌─────────────────────────────┐
│ GemmaTrans              ⚙   │
│ (自动 · 中文 → English)      │   语向已实化（detected→target）
│ ┌─────────────────────────┐ │
│ │ 这段文字需要被翻译……  (×) │ │   输入卡收缩为已输入内容
│ │                    (■停止)│ │   发送钮变停止钮（可取消生成）
│ └─────────────────────────┘ │
│ ┌─────────────────────────┐ │
│ │ This text needs to be   │ │   译文卡，流式生长
│ │ trans▍                  │ │   accent 光标闪烁
│ │ ─────────────────────── │ │
│ │ 中文 → English    (⧉灰) │ │   拷贝禁用（半透明）
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

### 3.6 翻译完成

```
│ ┌─────────────────────────┐ │
│ │ This text needs to be   │ │
│ │ translated…             │ │   光标消失
│ │ ─────────────────────── │ │
│ │ 中文 → English      (⧉) │ │   拷贝可用；点击→图标变✓+轻触感
│ └─────────────────────────┘ │   超长截断时 caption 追加「·已截断」
```

### 3.7 设置 sheet（`presentationDetents([.medium, .large])`）

```
┌─────────────────────────────┐
│        设置          [完成]  │
│ 目标语言                     │
│ ┌─────────────────────────┐ │
│ │ 中文译为      English ▾  │ │   targetForChinese
│ │ 其他语言译为   简体中文 ▾  │ │   targetDefault
│ └─────────────────────────┘ │
│ 模型                         │
│ ┌─────────────────────────┐ │
│ │ Gemma 4 E2B   已就绪·3.6GB│ │   就绪状态唯一的常驻可见处
│ │ 使用国内源        (○──)  │ │   footnote:重新下载时生效
│ └─────────────────────────┘ │
│ 系统集成                     │
│ ┌─────────────────────────┐ │
│ │ 设为系统翻译 App       ↗ │ │   跳系统设置（引导卡的常驻入口）
│ └─────────────────────────┘ │
│ 关于                         │
│ ┌─────────────────────────┐ │
│ │ 版本 1.0.0 · 完全离线运行 │ │
│ │ 隐私声明              ↗ │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

## 4. 系统翻译面板（TranslationProvider 扩展）轻量版

硬约束（spike 实测）：扩展进程 221MB、模型不可能进来；扩展不能后台唤醒主 app，
但面板内用户点按跳转主 app 是合法交互。设计目标：**让「跳一下」感觉像功能，不像道歉**。

```
┌─────────────────────────────┐   系统托管面板（宿主 app 原地弹出）
│ ❝ The quick brown fox       │   选中文字预览：.body、3 行截断、
│   jumps over the lazy…  ❞   │   secondaryLabel、首行 ❝ 装饰引号
│                             │
│ ┌─────────────────────────┐ │
│ │  在 GemmaTrans 中翻译  ↗ │ │   唯一主按钮，全宽 capsule accent
│ └─────────────────────────┘ │   （iOS26 glass，18.4 borderedProminent）
│  本地模型翻译 · 文本不上传     │   .footnote tertiaryLabel 居中——
└─────────────────────────────┘   把降级理由讲成隐私承诺
```

- **体面的关键是接力零摩擦**：点按 → 选中文字写入 App Group（`pendingHandoffText` +
  时间戳）→ deep link `gemmatrans://translate` 拉起主 app → 主 app 启动即把文本灌入
  输入卡并**自动开始流式翻译**。用户总成本 = 多点一下，到手即是滚动中的译文
- 文案绝不出现「内存不足/无法在此翻译」之类的自我矮化；说的是「GemmaTrans 在本地
  运行完整模型」——大模型进不了 221MB 面板是事实，把它表述成产品选择
- **模型未下载变体**：预览区不变，按钮变「打开 GemmaTrans 下载模型」，footnote 改为
  「首次使用需下载 3.6GB 本地模型」。文本同样接力，下载完成后自动翻译（v1 简化：
  进入输入卡等待即可）
- 无选中文字（理论不可达，`SelectedTextScene` 必有 inputText）：兜底显示同款按钮无预览
- 面板高度自适应内容（约 160~200pt），不抢宿主 app 的屏
- ⚠️ 落地前小验证：扩展 SwiftUI 场景内 `@Environment(\.openURL)` 能否拉起主 app
  （ExtensionKit 扩展通常可以，需真机确认）；不行则回退 `UIApplication` 不可用时的
  备选——预览 + 「拷贝原文」+ 文字引导「打开 GemmaTrans 粘贴翻译」（体验降一档，仍体面）

## 5. 落地清单（供实现代理执行）

新增目录约定：`AppiOS/GemmaTransiOS/Views/`、`AppiOS/GemmaTransiOS/Theme.swift`。
XcodeGen `project.yml` 按目录收文件，无需逐个登记。构建命令记得 `-skipMacroValidation`。

| # | 文件 | 动作 | 内容 | 预估 |
|---|---|---|---|---|
| 1 | `GemmaTransiOS/Theme.swift` | 新增 | 间距/圆角常量、`adaptiveGlassButton()`（iOS26 glassEffect / 18.4 回退）、拷贝触感 helper | ~70 行 |
| 2 | `GemmaTransiOS/Assets.xcassets` | 新增 | `AccentColor` 双值（#1E8E7E / #5BD6C0）；App 图标占位不在本期 | 配置 |
| 3 | `GemmaTransiOS/Views/TranslatorView.swift` | 新增 | 工作区：语向 pill、输入卡（粘贴/清除/计数/发送-停止钮）、译文卡（光标/拷贝/语向 caption）、加载 pill；内嵌 `@Observable TranslatorModel`（translate/cancel、detected/target 透出、拷贝态） | ~260 行 |
| 4 | `GemmaTransiOS/Views/OnboardingView.swift` | 新增 | idle/downloading/failed 三态（3.1–3.3 线框），环形进度、字节行、失败态源开关；国内源 Toggle 的 `@AppStorage` 从现 ContentView 迁来 | ~170 行 |
| 5 | `GemmaTransiOS/Views/SettingsSheet.swift` | 新增 | 3.7 线框；读写 `AppSettings.load/save(suiteName: ModelStore.settingsSuite)`；「设为系统翻译 App」跳 `UIApplication.openSettingsURLString`（能否直达翻译默认 App 设置页需查 URL，查不到就开本 app 设置页） | ~130 行 |
| 6 | `GemmaTransiOS/Views/SystemTranslateTipCard.swift` | 新增 | 引导卡 + `@AppStorage("tipDismissed")` | ~50 行 |
| 7 | `GemmaTransiOS/ContentView.swift` | 重写 | 只剩状态路由（2.1）+ `isIdleTimerDisabled` 的 onChange（现有逻辑原样保留）+ sheet 挂载 | 收缩到 ~60 行 |
| 8 | `GemmaTransiOS/GemmaTransiOSApp.swift` | 修改 | `onOpenURL` + 启动时消费 `pendingHandoffText`（>60s 的丢弃），灌入 TranslatorModel 并自动翻译 | +~30 行 |
| 9 | `Shared/ModelStore.swift` | 修改 | 增加 `handoffTextKey`/`handoffDateKey` 常量与读写 helper | +~15 行 |
| 10 | `TranslationProvider/TranslationProviderExtension.swift` | 重写 | 删除 `SpikePanelView` 全部探针代码；新 `HandoffPanelView`（第 4 节两个变体 + openURL 验证） | ~90 行 |
| 11 | `AppiOS/project.yml` + 主 app `Info.plist` | 修改 | 注册 URL scheme `gemmatrans`（CFBundleURLTypes） | 配置 |

执行顺序建议：1→2→4（onboarding 可独立验收）→3→6→7（主屏成型）→5→9→8→11→10
（接力链路最后通）。每步真机暗色模式过一眼再继续；spike 探针删除发生在第 10 步，
此前面板保持现状不影响主 app 改造。

### 验收要点

- 暗色模式下逐状态截图对照第 3 节线框；浅色不破即可
- 就绪态屏幕上**不存在**任何引擎状态文案
- 下载失败画面无红色、无原始 error 字符串（人话短句来自 `engineLoadFailureMessage`）
- 流式期间可停止；拷贝有触感反馈与 ✓ 确认
- 动态字体 XL 档不破版；`reduceMotion` 下光标不闪
- 面板→主 app 接力：选中→翻译→点按→主 app 已在流式输出，全程 ≤ 加载耗时 + 1 次点按

## 不做（本期 YAGNI）

历史记录、收藏、多模型切换、自定义主题、App 图标重绘、iPad 布局、横屏专项、
输入卡语音/相机入口、译文朗读。空态插画也不做——键盘弹起后那块区域不存在。
