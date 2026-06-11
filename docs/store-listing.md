# App Store 提审材料（粘贴用）

## 1. 商店描述

### 中文

**GemmaTrans —— 完全离线的本地 AI 划词翻译**

选中文字，按下快捷键，译文即刻浮现。GemmaTrans 把 Google 开源的 Gemma 4 大语言模型装进你的 menu bar，所有翻译在你的 Mac 上本地完成——不联网、不上传、零订阅。

- **划词即译**：任意 app 中选中文字按 ⌥D（可自定义），浮窗流式显示译文
- **智能双向**：自动识别语言——外文译中文，中文译英文，目标语言可自定义
- **完全离线**：翻译过程零网络请求，断网照用；你的文字永远不离开这台 Mac
- **开发者友好**：可选开启本地 API（OpenAI 兼容），PopClip、Bob、Raycast 等工具直连
- **按机器自动调优**：根据内存自动配置引擎参数，16GB 起步流畅运行

首次启动自动下载 Gemma 4 模型（约 2.4GB），并授予"辅助功能"权限用于读取选中文本。需要 Apple Silicon Mac。

### English

**GemmaTrans — Fully Offline AI Translation, One Hotkey Away**

Select text anywhere, press a hotkey, and the translation streams into a floating panel. GemmaTrans runs Google's open-source Gemma 4 LLM entirely on your Mac — no cloud, no upload, no subscription.

- **Select & translate**: works in any app via a customizable global hotkey (⌥D)
- **Smart bidirectional**: auto-detects language — foreign → Chinese, Chinese → English (both configurable)
- **Truly offline**: zero network requests during translation; your text never leaves your Mac
- **Developer friendly**: optional local OpenAI-compatible API for PopClip, Bob, Raycast and more
- **Auto-tuned**: engine parameters adapt to your machine's memory; runs smoothly from 16GB

First launch auto-downloads the Gemma 4 model (~2.4GB) and asks for Accessibility permission to read selected text. Requires Apple Silicon.

## 2. 审核备注（App Review Notes）

> GemmaTrans is a local-only translation utility built on Google's open-source Gemma 4 model (Apache 2.0) running via LiteRT-LM on-device inference.
>
> **Why Accessibility permission**: the app reads the text the user has actively selected (via the Accessibility API's selected-text attribute) when — and only when — the user presses the global hotkey. The text is passed to the on-device model for translation and displayed in a floating panel. No keylogging, no background monitoring, no data ever leaves the device.
>
> **Network usage**: the only network operation is the one-time model download from Hugging Face (user-initiated, in-app guidance). Translation itself performs zero network requests. The optional local HTTP server binds to 127.0.0.1 only and exists so the user's own tools (e.g. PopClip) can call the translator.
>
> **To test**: launch the app → menu bar icon appears and the Gemma 4 model (~2.4GB) downloads automatically (progress shown in the menu). Once the status shows ready, select any text in Notes/Safari and press Option+D; grant Accessibility permission when prompted. A floating panel streams the translation.

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

## 4. 提审 Checklist

- [ ] App Store Connect 新建 macOS App，bundle id `com.gemmatrans.GemmaTrans`，名称 GemmaTrans（被占则备选 "GemmaTrans 本地翻译"）
- [ ] 分类：效率（Productivity）；价格：免费
- [ ] 截图 ≥3 张，1280×800 或 2560×1600（建议：划词浮窗、菜单栏状态、设置页性能区）
- [ ] 隐私问卷：全部"不收集"；隐私政策 URL（上节全文挂任意可访问页面）
- [ ] 出口合规：仅使用豁免加密（HTTPS）→ 选"是，符合豁免"
- [ ] 年龄分级：4+
- [ ] 审核备注粘贴上文第 2 节；附演示视频链接更稳（可选）
- [ ] 上传：`dist/mas/GemmaTrans.pkg` 经 Transporter.app 拖拽上传
