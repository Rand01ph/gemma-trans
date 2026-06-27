# App Store 提审材料（粘贴用）

## 1. 商店描述

### 中文

**GemmaTrans —— 完全离线的本地 AI 划词翻译**

选中文字，按下快捷键，译文即刻浮现。GemmaTrans 把 Google 开源的 Gemma 4 大语言模型装进你的 menu bar，所有翻译在你的 Mac 上本地完成——不联网、不上传、零订阅。

- **划词即译**：任意 app 中选中文字按 ⌥⌘T（系统「服务」快捷键，可改键），浮窗流式显示译文
- **智能双向**：自动识别语言——外文译中文，中文译英文，目标语言可自定义
- **完全离线**：翻译过程零网络请求，断网照用；你的文字永远不离开这台 Mac
- **开发者友好**：可选开启本地 HTTP API（仅监听 127.0.0.1），PopClip、Bob、Raycast 等工具直连
- **按机器自动调优**：根据内存自动配置引擎参数，16GB 起步流畅运行

三种译法：① 在主窗口粘贴/输入文字翻译；② 任意 app 选中文字后按 ⌥⌘T（系统「服务」快捷键，可在系统设置改键）一键翻译选中内容，无需先复制；③ 复制文字后按 ⌥D 翻译剪贴板内容。首次启动自动下载 Gemma 4 模型（约 2.4GB）。需要 Apple Silicon Mac。

### English

**GemmaTrans — Fully Offline AI Translation, One Hotkey Away**

Select text anywhere, press a hotkey, and the translation streams into a floating panel. GemmaTrans runs Google's open-source Gemma 4 LLM entirely on your Mac — no cloud, no upload, no subscription.

- **Select & translate**: works in any app via a macOS Services shortcut (⌥⌘T, rebindable)
- **Smart bidirectional**: auto-detects language — foreign → Chinese, Chinese → English (both configurable)
- **Truly offline**: zero network requests during translation; your text never leaves your Mac
- **Developer friendly**: optional local HTTP API (binds to 127.0.0.1 only) for PopClip, Bob, Raycast and more
- **Auto-tuned**: engine parameters adapt to your machine's memory; runs smoothly from 16GB

Three ways to translate: (1) paste or type text in the main window; (2) select text in any app and press ⌥⌘T (a macOS Services shortcut — rebindable in System Settings) to translate the selection in one keystroke, no copying needed; (3) copy text and press ⌥D to translate the clipboard. First launch auto-downloads the Gemma 4 model (~2.4GB). Requires Apple Silicon. No Accessibility permission required.

## 2. 审核备注（App Review Notes）

> GemmaTrans is a local-only translation utility built on Google's open-source Gemma model (Apache 2.0) running fully on-device. There is no ChatGPT/OpenAI integration and no third-party AI service of any kind — all translation is performed by the on-device Google Gemma model. The app never connects to OpenAI or any generative-AI server.
>
> **Re: Guideline 5 / "OpenAI"**: a previous build's marketing text described the optional local HTTP endpoint as "OpenAI-compatible" only to tell developers it accepts the common `/v1/chat/completions` request shape used by tools like PopClip. The app does NOT call OpenAI and contains no OpenAI/ChatGPT functionality. We have removed the word "OpenAI" from all metadata. The optional local server binds to 127.0.0.1 (loopback) only and simply forwards requests to the on-device Gemma model; it can be turned off.
>
> **Re: Guideline 2.4.5 / Accessibility**: this version does NOT request or use the Accessibility API at all. Text reaches the translator three ways, each user-initiated: (1) the user pastes or types text into the app's main window; (2) the user selects text in any app and invokes our macOS Services item "Translate with GemmaTrans" — it has a default shortcut ⌥⌘T, rebindable in System Settings › Keyboard › Keyboard Shortcuts › Services; (3) the user copies text and presses the in-app hotkey to translate the clipboard. No Accessibility permission, no keylogging, no background monitoring.
>
> **Network usage**: the only network operation is the one-time model download (user-visible progress, in the main window). Translation itself performs zero network requests; the app works fully offline once the model is downloaded.
>
> **To test (Re: Guideline 2.1a / download)**: GemmaTrans is a menu-bar app (no Dock icon). On launch its main window opens automatically and shows the Gemma model (~2.4GB) downloading with a live progress bar; a menu-bar icon is also added. If the download ever stalls, a "Retry" button appears in the window. Once the status shows "Ready", the simplest way to test translation is to paste any text into the window's box and click "Translate" — the result streams in, with no permission prompts. You can also select text in any app and choose Services › "Translate with GemmaTrans" (its ⌥⌘T shortcut works too; if pressing it does nothing, enable it once under System Settings › Keyboard › Keyboard Shortcuts › Services › Text). No Accessibility or other permission is ever requested.

## 3. 隐私政策（全文，可挂任意静态页面）

**GemmaTrans 隐私政策 / Privacy Policy**（更新日期 / Last updated: 2026-06-10）

GemmaTrans 不收集、不存储、不传输任何用户数据。
GemmaTrans does not collect, store, or transmit any user data.

- 您选中并翻译的文本仅在本设备内存中处理，翻译由本地模型完成，不经过任何服务器。
  Text you select for translation is processed in memory on your device by a local model. It is never sent to any server.
- 应用不包含任何分析、广告或第三方 SDK。
  The app contains no analytics, advertising, or third-party SDKs.
- 唯一的网络行为是您主动发起的模型文件下载（来自 Hugging Face）。
  The only network activity is the model download you explicitly initiate (from Hugging Face).
- 本地 API 仅监听本机回环地址（127.0.0.1），默认可关闭。
  The optional local API binds to 127.0.0.1 only and can be disabled.

联系方式 / Contact: tanyawei1991@gmail.com

## 4. 重新提审 Checklist（针对 1.0(3) 三条拒审，已落地修法 → build 1.0(4)）

被拒三条 → 本次修法：
- **Guideline 5（OpenAI）**：描述与截图删掉所有 "OpenAI" 字样（本文件第 1 节描述已清；截图务必核对）。
- **Guideline 2.4.5（辅助功能）**：彻底移除辅助功能；改用 macOS「服务」(⌥⌘T) + 主窗口粘贴框 + ⌥D 翻译剪贴板。
- **Guideline 2.1a（下载空闲）**：启动即弹主窗口、显示下载进度条 + 失败「重试」按钮（不再是只有菜单栏的「装死」）。

提审步骤：
- [ ] App Store Connect → 该 App → 编辑「App 描述」，把旧描述里的 "OpenAI" 删掉，整体换成本文件第 1 节新描述（中 + 英）。
- [ ] 逐张核对「截图」里没有 "OpenAI"/"ChatGPT" 字样（Apple 把截图也算 metadata）；如有则重截。注意 app 现在是纯菜单栏 app、无 Dock 图标，截图别再出现 Dock 图标。
- [ ] 「App 审核信息 / Review Notes」粘贴本文件第 2 节全文（已说明无 OpenAI、无辅助功能、下载可见、如何测试）。
- [ ] 中国大陆区保持上架（已确认保留）。
- [ ] Xcode 打包上传：选 **GemmaTrans-MAS** scheme → Product → Archive → Organizer → Distribute App → **App Store Connect** → Upload（自动签名走 Apple Distribution，上传 **build 1.0(4)**）。
- [ ] ASC 新版本里选中 build **1.0 (4)**，出口合规/年龄分级沿用上次，Submit for Review。
