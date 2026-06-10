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
| `text` | string | 必填，待翻译文本（超过 4000 字符截断） |
| `target` | string? | 目标语言 BCP-47 码（如 `en`、`zh-Hans`）；缺省走智能双向 |
| `stream` | bool? | `true` 时返回 SSE 流 |

响应：`{"translation": "...", "detected": "en", "target": "zh-Hans", "truncated": false}`

SSE 流格式：若干 `data: {"delta": "..."}` → 一条 `data: {"translation": 全文, ...}` → `data: [DONE]`。

### `POST /v1/chat/completions`

OpenAI 兼容（含 `stream: true` SSE）。取最后一条 `user` 消息按智能双向翻译；`model` 字段与 system 消息被忽略——这是翻译器，不是通用聊天。

### `GET /health`

`{"status": "ready"}`（200）或 `{"status": "loading"}`（503）。

错误码：400（空文本/无效 JSON）、503（模型未加载 / 引擎忙超时 30s）。

## M2 预告

menu bar 常驻 app：全局热键（默认 `⌥D`）划词翻译、浮窗流式译文、设置界面。见 `docs/superpowers/plans/`。

## 架构

```
GemmaTransKit     核心库：LiteRT-LM 引擎封装、语言检测（NaturalLanguage）、提示词
GemmaTransServer  HTTP 层：FlyingFox，/translate + OpenAI 兼容 + SSE
gemma-trans-cli   命令行：spike / serve
```
