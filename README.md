# GemmaTrans

macOS 本地大模型划词翻译。基于 Google **Gemma 4 E4B** + **LiteRT-LM**（Metal GPU 加速），完全离线运行：

- **本地 HTTP API**（`127.0.0.1:8765`）：极简 `/translate` 接口 + **OpenAI 兼容** `/v1/chat/completions`，PopClip、Bob、Raycast 等工具直连
- **menu bar app**（M2）：全局热键划词翻译，浮窗流式显示译文
- **智能双向**：自动检测语言——中文 → 英文，其他语言 → 中文（目标语言可配置）

## 快速开始

### 1. 准备依赖与模型

```bash
git clone <本仓库> && cd gemma-trans
./Scripts/bootstrap.sh   # 浅克隆 LiteRT-LM（SPM unsafe flags 限制，必须本地引用）

# 下载模型（约 4GB，Hugging Face 需要已接受 Gemma 许可）
mkdir -p ~/Library/Application\ Support/GemmaTrans/models
curl -L -C - -o ~/Library/Application\ Support/GemmaTrans/models/gemma-4-E4B-it.litertlm \
  "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
```

### 2. 启动 API 服务

```bash
swift run gemma-trans-cli serve
# Model ready. Listening on http://127.0.0.1:8765
```

可用 `GEMMA_MODEL_PATH=/path/to/model.litertlm` 覆盖模型路径；`swift run gemma-trans-cli spike` 跑一次最小可行性验证。

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

# OpenAI 兼容接口
curl -s -X POST http://127.0.0.1:8765/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "Hello world"}]}'
```

## PopClip 集成

1. 保持 `gemma-trans-cli serve`（或 M2 的 app）运行
2. 在 Finder 中双击 `popclip/GemmaTrans.popclipext` 目录，PopClip 会提示安装
3. 任意 app 选中文字 → 点击 PopClip 弹条中的 GemmaTrans 图标 → 顶部显示译文

PopClip 也可以用其内置 OpenAI 扩展指向 `http://127.0.0.1:8765/v1`（API key 随意填）。

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

OpenAI 兼容（含 `stream: true` SSE）。取最后一条 `user` 消息按智能双向翻译；`model` 字段与 system 消息被忽略——这是翻译器，不是通用聊天。

### `GET /health`

`{"status": "ready"}`（200）或 `{"status": "loading"}`（503）。

错误码：400（空文本/无效 JSON）、503（模型未加载 / 引擎忙超时 30s）、500（引擎错误，`error` 字段含详情，常见于系统内存压力过高时 GPU 分配失败）。

引擎与服务日志：`~/Library/Logs/GemmaTrans/gemmatrans.log`（GUI app 无 stderr，排障看这里）。

## Menu bar app（划词翻译）

```bash
brew install xcodegen   # 首次
cd App && xcodegen generate
xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/GemmaTrans.app
```

- 启动后 menu bar 出现 💬 图标，模型加载完成（约 15s）后图标变实心，并在 `127.0.0.1:8765` 提供 API（app 与 CLI serve 二者跑一个即可，同时跑会端口冲突）
- **首次使用**：在任意 app 选中文字按 `⌥D`，系统会弹出"辅助功能"授权请求 → 系统设置中勾选 GemmaTrans → 重启 app
- 之后：选中文字 → `⌥D` → 鼠标旁浮窗流式显示译文（Esc 关闭，可一键复制）
- 不选文字按 `⌥D` 会提示"未检测到选中文本"
- 菜单"设置…"可改模型路径、目标语言、API 端口和热键
- 设置"性能"区默认按机器内存自动配置 KV cache 与输入上限（加载时还会按当前可用内存降档），也可手动覆盖

## 架构

```
GemmaTransKit     核心库：LiteRT-LM 引擎封装、语言检测（NaturalLanguage）、提示词
GemmaTransServer  HTTP 层：FlyingFox，/translate + OpenAI 兼容 + SSE
gemma-trans-cli   命令行：spike / serve
```
