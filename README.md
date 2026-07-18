# GemmaTrans

macOS 本地大模型划词翻译。基于 **MLX-Swift**（Apple Silicon 原生加速），支持多个本地翻译模型（Google **Gemma 4** / 腾讯混元 **Hy-MT2**），完全离线运行：

界面原则、组件规范与 Codex 匹配矩阵见 [DESIGN.md](DESIGN.md)。

- **本地 HTTP API**（`127.0.0.1:8765`）：极简 `/translate` 接口 + 兼容 `/v1/chat/completions` 请求格式，PopClip、Bob、Raycast 等工具直连
- **menu bar app**：全局热键划词翻译，浮窗流式显示译文
- **智能双向**：自动检测语言——中文 → 英文，其他语言 → 中文（目标语言可配置）
- **多模型可选**：内置 Gemma 4（E4B/E2B，4-bit）与腾讯混元 **Hy-MT2**（1.8B 翻译专用，4/8-bit）；设置页可下载、切换、删除模型，支持后台下载（边用边下）
- **性能可视**：翻译后显示每秒 token 速率（按模型分别记录），随时观察各模型快慢
- **模型下载**：首次启动按内存自动选 Gemma 档拉取（E4B≈4.9GB / E2B≈3.6GB），双源（HuggingFace / 国内 ModelScope）+ 断点续传

## 快速开始

### 构建并启动 API 服务

```bash
git clone https://github.com/Rand01ph/gemma-trans && cd gemma-trans
# MLX 的 Metal 着色器需要 xcodebuild（首次如提示缺 Metal 工具链：xcodebuild -downloadComponent MetalToolchain）
xcodebuild -scheme gemma-trans-cli -destination 'platform=macOS' -skipMacroValidation -derivedDataPath .build-cli build
.build-cli/Build/Products/Debug/gemma-trans-cli serve
# 首次自动下载模型 → Model ready. Listening on http://127.0.0.1:8765
```

国内网络可用镜像：启动前 `export HF_ENDPOINT=https://hf-mirror.com`。`gemma-trans-cli spike` 跑一次最小验证。

### 3. 调用

```bash
# 健康检查
curl -s http://127.0.0.1:8765/health

# 翻译（自动检测语言，英文→中文）
curl -s -X POST http://127.0.0.1:8765/translate -H 'Content-Type: application/json' \
  -d '{"text": "The quick brown fox jumps over the lazy dog."}'

# 流式（SSE）
curl -s -N -X POST http://127.0.0.1:8765/translate -H 'Content-Type: application/json' \
  -d '{"text": "今天天气真好", "stream": true}'

# /v1/chat/completions 接口
curl -s -X POST http://127.0.0.1:8765/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "Hello world"}]}'
```

## PopClip 集成

1. 保持 `gemma-trans-cli serve`（或 app）运行；用 app 时在菜单栏确认"本地 API"开启（默认已开）
2. 在 Finder 中双击 `popclip/GemmaTrans.popclipext` 目录，PopClip 会提示安装
3. 任意 app 选中文字 → 点击 PopClip 弹条中的 GemmaTrans 图标 → 顶部显示译文

PopClip 也可以用任何接受 `/v1/chat/completions` 的扩展指向 `http://127.0.0.1:8765/v1`（API key 随意填）。

## API 文档

### `POST /translate`

| 字段 | 类型 | 说明 |
|------|------|------|
| `text` | string | 必填，待翻译文本（超长截断；上限随机器自动调优，16GB 机器默认 1500 字符，可在设置中手动覆盖） |
| `target` | string? | 目标语言 BCP-47 码（如 `en`、`zh-Hans`）；缺省走智能双向 |
| `stream` | bool? | `true` 时返回 SSE 流 |

响应：`{"translation": "...", "detected": "en", "target": "zh-Hans", "truncated": false}`

SSE 流格式：若干 `data: {"delta": "..."}` → 一条 `data: {"translation": 全文, ...}` → `data: [DONE]`。

### `POST /v1/chat/completions`

兼容 `/v1/chat/completions` 请求格式（含 `stream: true` SSE），方便接受该格式的工具直连本地引擎。取最后一条 `user` 消息按智能双向翻译；`model` 字段与 system 消息被忽略——这是翻译器，不是通用聊天，且全程本地，不连任何外部服务。

### `GET /health`

`{"status": "ready"}`（200）或 `{"status": "loading"}`（503）。

错误码：400（空文本/无效 JSON）、503（模型未加载 / 引擎忙超时 30s）、500（引擎错误，`error` 字段含详情，常见于系统内存压力过高时 GPU 分配失败）。

引擎与服务日志：`~/Library/Logs/GemmaTrans/gemmatrans.log`（GUI app 无 stderr，排障看这里）。

API 可在菜单栏/设置中即时开关，无需重启。关闭后划词翻译不受影响——划词是进程内调用，不走端口。端口被其他程序占用时菜单会显示"API 失败"，划词照常可用；若占用者是另一个 GemmaTrans 实例（如 CLI serve），app 会拒绝启动以避免加载两份模型。

## Menu bar app（划词翻译）

```bash
brew install xcodegen   # 首次
cd App && xcodegen generate
xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/GemmaTrans.app
```

- 启动后弹出主窗口（含模型下载进度），同时 menu bar 出现 💬 图标；模型加载完成（约 15s）后图标变实心，并在 `127.0.0.1:8765` 提供 API（app 与 CLI serve 二者跑一个即可，同时跑会端口冲突）
- **三种译法**（均无需任何系统权限）：
  - 主窗口里粘贴/输入文字 → 点「翻译」流式显示译文
  - 任意 app 选中文字 → 按 `⌥⌘T` 一键翻译选中内容，**无需先复制**；也可从「服务」菜单点「Translate with GemmaTrans」
    - 这是 macOS「服务」快捷键，默认 `⌥⌘T`。macOS 不一定会自动启用声明的默认值——若按了没反应，去 系统设置 › 键盘 › 键盘快捷键 › 服务 › 文本，勾选并确认 Translate with GemmaTrans 的快捷键（一次性，之后长期生效；也可在这里改键）
  - 复制文字后按 `⌥D` → 翻译剪贴板内容（鼠标旁浮窗流式显示，Esc 关闭，可一键复制）
- 菜单"设置…"可改目标语言、API 端口和剪贴板热键
- 设置"性能"区默认按机器内存自动配置 KV cache 与输入上限（加载时还会按当前可用内存降档），也可手动覆盖

## 架构

```
GemmaTransKit     核心库：MLX-Swift 引擎封装、语言检测（NaturalLanguage）、提示词、按内存自动调优
GemmaTransServer  HTTP 层：FlyingFox，/translate + /v1/chat/completions + SSE
gemma-trans-cli   命令行：spike / serve
```
