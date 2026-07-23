# App Store 提审材料（粘贴用）

## 0. 产品页字段

| 字段 | 简体中文 | English (U.S.) |
| --- | --- | --- |
| 名称 | GemmaTrans | GemmaTrans |
| 副标题 | 离线 AI 划词翻译 | Private Offline Translation |
| 推广文本 | 选中文字，按下快捷键，译文即刻浮现。GemmaTrans 2 采用克制而精致的 Liquid Glass 设计，带来完全离线的本地 AI 翻译，支持固定浮窗、四款按需模型、自动下载源回退与本地 API。 | Private, offline translation on your Mac. GemmaTrans 2 adds a refined Liquid Glass interface, a pinnable result panel, four on-device models, and a local API. |
| 关键词 | 翻译,离线翻译,AI翻译,划词翻译,本地模型,Gemma,隐私,双语,菜单栏,快捷键 | translation,offline,AI,local,Gemma,privacy,hotkey,menu bar,bilingual,LLM |
| 技术支持网址 | https://github.com/Rand01ph/gemma-trans | https://github.com/Rand01ph/gemma-trans |
| 营销网址 | https://github.com/Rand01ph/gemma-trans | https://github.com/Rand01ph/gemma-trans |

### 2.0.0 此版本的新增内容

#### 简体中文

GemmaTrans 2.0 带来一次完整的 macOS 体验重构：

- 采用克制而精致的 Liquid Glass 设计，全面重构主窗口、设置页与快捷翻译浮窗
- 支持固定浮窗位置，连续翻译长文时保持视线稳定
- 四款本地模型由你按需下载和切换，首次启动不再自动下载
- Hugging Face 不可用时自动回退国内下载源
- 统一浅色、深色、按钮状态与窗口置顶行为
- 修复新版 Gemma 4 模型加载、长译文显示和连续请求覆盖问题

#### English

GemmaTrans 2.0 is a complete macOS experience refresh:

- A refined Liquid Glass design across the main window, settings, and translation panel
- Pin the panel while translating long documents paragraph by paragraph
- Choose and download any of four on-device models; nothing downloads on first launch
- Automatic download fallback when Hugging Face is unavailable
- Refined Light and Dark appearances, button states, and window behavior
- Fixes for current Gemma 4 checkpoints, long results, and rapid consecutive requests

## 1. 商店描述

### 中文

**GemmaTrans 2 —— 完全离线的本地 AI 划词翻译**

选中文字，按下快捷键，译文即刻浮现。GemmaTrans 把翻译模型留在你的 Mac 上，所有翻译都在本地完成——不上传、零订阅，模型下载完成后断网也能使用。

- **划词即译**：任意 app 中选中文字按 ⌥⌘T（系统「服务」快捷键，可改键），浮窗流式显示译文
- **固定浮窗**：逐段翻译长文时固定阅读位置，连续结果在同一个精致浮窗中更新
- **智能双向**：自动识别语言——外文译中文，中文译英文，目标语言可自定义
- **完全离线**：翻译过程零网络请求，断网照用；你的文字永远不离开这台 Mac
- **四个本地模型**：按需选择 Gemma 4 E4B/E2B 或 Hy-MT2 4/8-bit，不会在首次启动时自动下载
- **开发者友好**：可选开启本地 HTTP API（仅监听 127.0.0.1），PopClip、Bob、Raycast 等工具直连
- **按机器自动调优**：根据内存自动配置引擎参数，16GB 起步流畅运行

三种译法：① 在主窗口粘贴或输入文字；② 任意 app 选中文字后按 ⌥⌘T，无需先复制；③ 复制文字后按 ⌥D 翻译剪贴板。首次启动请在“设置 › 模型”选择并下载模型；下载优先 Hugging Face，不可用时自动回退 ModelScope。需要 Apple Silicon Mac 与 macOS 26 或更高版本。

### English

**GemmaTrans 2 — Fully Offline AI Translation, One Hotkey Away**

Select text anywhere, press a hotkey, and the translation streams into a floating panel. GemmaTrans keeps its translation models on your Mac — no text upload, no subscription, and fully offline after a model is downloaded.

- **Select & translate**: works in any app via a macOS Services shortcut (⌥⌘T, rebindable)
- **Pin the result panel**: keep a stable reading position while translating a document paragraph by paragraph
- **Smart bidirectional**: auto-detects language — foreign → Chinese, Chinese → English (both configurable)
- **Truly offline**: zero network requests during translation; your text never leaves your Mac
- **Four local models**: choose Gemma 4 E4B/E2B or Hy-MT2 4/8-bit; the app never downloads a model without your action
- **Developer friendly**: optional local HTTP API (binds to 127.0.0.1 only) for PopClip, Bob, Raycast and more
- **Auto-tuned**: engine parameters adapt to your machine's memory; runs smoothly from 16GB

Three ways to translate: (1) paste or type text in the main window; (2) select text in any app and press ⌥⌘T (a macOS Services shortcut, rebindable in System Settings), no copying needed; (3) copy text and press ⌥D to translate the clipboard. On first launch, choose and download a model under Settings › Models. Downloads use Hugging Face first and automatically fall back to ModelScope when unavailable. Requires Apple Silicon and macOS 26 or later. No Accessibility permission required.

## 2. 审核备注（App Review Notes）

> GemmaTrans is a local-only translation utility built on Google's open-source Gemma model (Apache 2.0) running fully on-device. There is no ChatGPT/OpenAI integration and no third-party AI service of any kind — all translation is performed by the on-device Google Gemma model. The app never connects to OpenAI or any generative-AI server.
>
> **Re: Guideline 5 / "OpenAI"**: a previous build's marketing text described the optional local HTTP endpoint as "OpenAI-compatible" only to tell developers it accepts the common `/v1/chat/completions` request shape used by tools like PopClip. The app does NOT call OpenAI and contains no OpenAI/ChatGPT functionality. We have removed the word "OpenAI" from all metadata. The optional local server binds to 127.0.0.1 (loopback) only and simply forwards requests to the on-device Gemma model; it can be turned off.
>
> **Re: Guideline 2.4.5 / Accessibility**: this version does NOT request or use the Accessibility API at all. Text reaches the translator three ways, each user-initiated: (1) the user pastes or types text into the app's main window; (2) the user selects text in any app and invokes our macOS Services item "Translate with GemmaTrans" — it has a default shortcut ⌥⌘T, rebindable in System Settings › Keyboard › Keyboard Shortcuts › Services; (3) the user copies text and presses the in-app hotkey to translate the clipboard. No Accessibility permission, no keylogging, no background monitoring.
>
> **Network usage**: the only external network operation is a model download explicitly started by the user under Settings › Models. The app tries Hugging Face first and may automatically fall back to ModelScope when that source is unavailable. Translation itself performs zero network requests; the app works fully offline once a model is downloaded.
>
> **To test (Re: Guideline 2.1a / download)**: GemmaTrans is a menu-bar app (no Dock icon). On launch its main window opens automatically and shows that no model has been selected; it does not connect to the network. Open Settings › Models, click Download for any model, wait for the visible progress to complete, then click Use. Once the status shows Ready, paste text into the main window and click Translate. You can also select text in any app and choose Services › "Translate with GemmaTrans" (its ⌥⌘T shortcut works too; if pressing it does nothing, enable it once under System Settings › Keyboard › Keyboard Shortcuts › Services › Text). No Accessibility permission is requested.

## 3. 隐私政策（全文，可挂任意静态页面）

**GemmaTrans 隐私政策 / Privacy Policy**（更新日期 / Last updated: 2026-07-19）

GemmaTrans 不收集、不存储、不传输任何用户数据。
GemmaTrans does not collect, store, or transmit any user data.

- 您选中并翻译的文本仅在本设备内存中处理，翻译由本地模型完成，不经过任何服务器。
  Text you select for translation is processed in memory on your device by a local model. It is never sent to any server.
- 应用不包含任何分析、广告或第三方 SDK。
  The app contains no analytics, advertising, or third-party SDKs.
- 唯一的外部网络行为是您主动发起的模型文件下载（优先 Hugging Face，不可用时自动回退 ModelScope）。
  The only external network activity is a model download you explicitly initiate (Hugging Face first, with automatic fallback to ModelScope when unavailable).
- 本地 API 仅监听本机回环地址（127.0.0.1），默认可关闭。
  The optional local API binds to 127.0.0.1 only and can be disabled.

联系方式 / Contact: tanyawei1991@gmail.com

## 4. GemmaTrans 2.0 提审 Checklist

历史审核关注点与当前处理：
- **Guideline 5（OpenAI）**：描述与截图删掉所有 "OpenAI" 字样（本文件第 1 节描述已清；截图务必核对）。
- **Guideline 2.4.5（辅助功能）**：彻底移除辅助功能；改用 macOS「服务」(⌥⌘T) + 主窗口粘贴框 + ⌥D 翻译剪贴板。
- **Guideline 2.1a（下载空闲）**：启动即弹主窗口并明确提示选择模型；下载只由用户点击触发，提供进度、失败说明和重试。

提审步骤：
- [ ] App Store Connect → 该 App → 编辑「App 描述」，把旧描述里的 "OpenAI" 删掉，整体换成本文件第 1 节新描述（中 + 英）。
- [ ] 逐张核对「截图」里没有 "OpenAI"/"ChatGPT" 字样（Apple 把截图也算 metadata）；如有则重截。注意 app 现在是纯菜单栏 app、无 Dock 图标，截图别再出现 Dock 图标。
- [ ] 「App 审核信息 / Review Notes」粘贴本文件第 2 节全文（已说明无 OpenAI、无辅助功能、下载可见、如何测试）。
- [ ] 中国大陆区保持上架（已确认保留）。
- [ ] 在 App Store Connect 创建 **2.0.0** 版本，并确认当前最大 build 号。
- [ ] 使用正式版、包含 macOS 26 SDK 的 Xcode 构建 **GemmaTrans-MAS**；build 号必须高于 ASC 已有值。
- [ ] 上传后先验证 TestFlight 安装、首次无自动下载、四模型下载/切换、⌥⌘T、⌥D 和本地 API。
- [ ] ASC 新版本关联 2.0.0 build，完成出口合规、年龄分级和隐私信息后 Submit for Review。
