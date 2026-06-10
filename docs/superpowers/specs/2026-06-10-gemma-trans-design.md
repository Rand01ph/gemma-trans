# GemmaTrans 设计文档

日期：2026-06-10
状态：已确认（用户评审通过）

## 目标

在 macOS 上实现基于本地 Gemma 4 模型的划词翻译：

1. 一个常驻 menu bar 的原生 SwiftUI app，全局热键划词翻译，浮窗流式显示译文
2. 同时暴露本地 HTTP API（`127.0.0.1:8765`），供 PopClip 等第三方工具调用

推理框架使用 Google 官方 LiteRT-LM Swift（SPM：`https://github.com/google-ai-edge/LiteRT-LM`），模型文件为 `.litertlm` 格式。

## 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 产品形态 | 单 app：内嵌引擎 + 热键划词 + 本地 HTTP API | 一份代码两种用法；单进程模型只加载一次 |
| 默认模型 | Gemma 4 E4B（`litert-community/gemma-4-E4B-it-litert-lm`） | 用户硬件为 M2 / 16GB RAM；E4B 占用约 4-5GB，质量/速度平衡最佳。模型路径可配置 |
| 语言策略 | 智能双向：检测为中文 → 译英文；其他语言 → 译简体中文 | 无需手动选择；两个目标语言均可在设置中修改 |
| 交付节奏 | 两个里程碑：M1 = Kit + Server（可配 PopClip）；M2 = menu bar UI + 热键 + 浮窗 | 最快见效；先验证新框架可行性再投入 UI |

## 架构

Swift Package workspace + Xcode app 工程，三层：

### GemmaTransKit（核心库，无 UI 依赖）

- **`TranslationEngine`**（actor）：封装 LiteRT-LM 的 `Engine`。启动时加载一次模型（Metal GPU backend：`EngineConfig(modelPath:backend: .gpu)`）。请求串行排队（并发 = 1）。每次翻译创建一次性 `Conversation`，不保留对话历史，避免上下文污染。
- **`LanguageDetector`**：基于系统 `NaturalLanguage` 框架（`NLLanguageRecognizer`），毫秒级、不消耗模型。中文 → 目标 `en`；其他 → 目标 `zh-Hans`。
- **`PromptBuilder`**：翻译提示词模板。系统指令要求只输出译文，不解释、不加引号、保留原文格式。
- **`AppSettings`**：模型路径、HTTP 端口、热键、两个目标语言（UserDefaults 持久化）。

### GemmaTransServer（HTTP 层）

- HTTP 框架：[FlyingFox](https://github.com/swhitty/FlyingFox)（纯 Swift、零依赖、async/await、适合 app 内嵌）。
- 仅绑定 `127.0.0.1`（不暴露局域网），默认端口 8765。
- 接口：
  - `POST /translate`：请求 `{"text": "...", "target": "可选", "stream": false}` → 响应 `{"translation": "...", "detected": "en", "target": "zh-Hans"}`；`stream: true` 时走 SSE。
  - `POST /v1/chat/completions`：OpenAI 兼容（含 SSE 流式），使 PopClip 现成 OpenAI 扩展、Bob、Raycast 等零改造直连。
  - `GET /health`：返回引擎状态（loading / ready / error）。
- 通过协议（`Translating`）依赖引擎，便于测试时注入 mock。

### GemmaTrans.app（SwiftUI menu bar 常驻）

- `MenuBarExtra`：引擎状态指示、API 服务开关、设置窗口入口、退出。
- 全局热键：默认 `⌥D`，使用 sindresorhus/KeyboardShortcuts 库，可自定义。
- 取词策略：优先 Accessibility API（`AXUIElement` 焦点元素的 selected text）；失败（如部分 Electron 应用）则模拟 ⌘C（CGEvent）兜底，取词前保存剪贴板、取词后恢复。
- 浮窗：非激活式 `NSPanel`，出现在鼠标位置附近，流式渲染译文（本地模型首字延迟明显，流式为刚需），Esc 或点击外部关闭，提供"复制"按钮。
- 首次启动引导授权"辅助功能"权限。
- 不上架 App Store（嵌 HTTP server + AX 权限需关闭 sandbox），本地构建直接使用。

## 数据流

- 划词路径：热键 → 取词（AX → ⌘C 兜底）→ NL 语言检测 → PromptBuilder → TranslationEngine 流式生成 → 浮窗逐字显示。
- PopClip 路径：选中文字 → PopClip 扩展 → `POST 127.0.0.1:8765/translate`（或 OpenAI 兼容口）→ 显示结果。交付物包含现成的 PopClip 扩展配置。

## 错误处理

- 模型文件缺失：设置页给出 Hugging Face 下载链接与下载命令；选择文件后自动加载。
- 模型加载失败 / 内存不足：menu bar 图标变红 + 系统通知；HTTP 返回 503。
- 取词为空：浮窗短暂提示"未检测到选中文本"。
- 输入限长：默认 4000 字符，超出截断并提示；排队请求 30 秒超时。

## 测试策略

- 纯单元测试（不依赖模型）：`LanguageDetector`、`PromptBuilder`、HTTP 路由 / JSON / SSE（注入 mock 引擎）。
- 引擎集成测试：依赖本地模型文件，单独标记，手动触发。
- 里程碑验收：
  - M1：`curl` 翻译成功；PopClip 实际配通。
  - M2：在任意 app 中划词按热键，浮窗流式显示译文。

## 风险与备选

- **LiteRT-LM Swift 成熟度未知**（2026 年新框架）：M1 第一个任务即最小 spike——CLI 完成一次真实翻译。若不可行，备选 MLX-Swift（Apple 官方，同样支持 Gemma 4），架构其余部分不变。
- E4B 常驻约 4-5GB 内存：M2 16GB 下可接受。

## 明确不做（YAGNI）

翻译历史记录、OCR 截图翻译、多模型切换 UI（仅保留路径配置）、App Store 上架与公证分发、闲置自动卸载模型、自动更新。

## 参考

- LiteRT-LM Swift 文档：https://developers.google.com/edge/litert-lm/swift
- Gemma 4 模型页：https://developers.google.com/edge/litert-lm/models/gemma-4
- 默认模型权重：https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
