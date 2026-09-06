# GemmaTrans

macOS 本地大模型划词翻译。基于 **MLX-Swift** 与策展的静态 CPU 运行时，在 Apple Silicon 上运行 Google **Gemma 4** 与腾讯混元 **Hy-MT2**；模型下载完成后，翻译文本不会离开你的 Mac。

[下载正式版](https://github.com/Rand01ph/gemma-trans/releases/latest) · [App Store](https://apps.apple.com/app/id6778876828) · [2.1 更新说明](docs/release-notes-2.1.md) · [设计系统](DESIGN.md) · [隐私政策](PRIVACY.md) · [许可证](LICENSE)

> GemmaTrans 2.1 要求 **Apple Silicon Mac** 与 **macOS 15 或更高版本**。macOS 26 使用 Liquid Glass，macOS 15 使用兼容的系统材质界面。

## 2.1 亮点

- **本地 HTTP API**（`127.0.0.1:8765`）：极简 `/translate` 接口 + 兼容 `/v1/chat/completions` 请求格式，PopClip、Bob、Raycast 等工具直连
- **Liquid Glass 新界面**：以克制的原生玻璃层级重构主窗口、三标签设置页和紧凑的结果优先翻译浮窗，完整适配浅色、深色与系统外观
- **划词与剪贴板快捷翻译**：macOS Service 处理当前选中文本，`⌥D` 翻译剪贴板；快捷键浮窗不会抢占主窗口
- **可固定的翻译浮窗**：逐段翻译长文时锁定浮窗位置，连续结果在同一位置更新；译文字号可在设置中调节
- **智能双向**：自动检测语言——中文 → 英文，其他语言 → 中文（目标语言可配置）
- **六款明确可选模型**：首次启动不自动下载；在原有 Gemma 4 E4B/E2B、Hy-MT2 4/8-bit 之外，新增约 440 MB 的 Hy-MT2 1.25-bit 轻量版与约 573 MB 的 2-bit 均衡版
- **固定文件完整性校验**：两款低比特模型直接下载固定 revision 的单个文件，并校验字节数与 SHA-256；Hugging Face 不可用时自动回退 ModelScope
- **自动下载源回退**：优先 Hugging Face，不可用时自动切换 ModelScope，无需手动选择国内源
- **稳定的模型管理**：新模型可以后台下载，不影响当前模型继续翻译；针对新版 Gemma 4 checkpoint 提供兼容错误提示
- **性能可视**：翻译后显示每秒 token 速率（按模型分别记录），随时观察各模型快慢

## 使用 App

1. 从 GitHub Releases 下载已签名并公证的 DMG，或从 Mac App Store 安装。
2. 首次启动进入“设置 › 模型”，选择一个模型并点击“下载”；下载完成后点击“使用”。
3. 在主窗口输入文本，或使用以下快捷方式：
   - 任意 App 中选中文字，按 `⌥⌘T` 调用 macOS Service；
   - 复制文本后按 `⌥D` 翻译剪贴板；
   - 固定翻译浮窗后，可逐段触发翻译而不改变阅读位置。

模型体积约为：Hy-MT2 1.25-bit 440 MB、Hy-MT2 2-bit 573 MB、Hy-MT2 4-bit 1.1GB、Hy-MT2 8-bit 1.9GB、Gemma 4 E2B 3.6GB、Gemma 4 E4B 4.9GB。下载属于用户主动操作；下载完成后翻译可完全离线进行。

### Hy-MT2 低比特模型本地测试参考

以下数据来自发布前使用与 App 完全相同的静态 XCFramework 运行时进行的本地门禁测试，仅用于帮助选择模型，不代表所有文本和设备的固定性能。

测试环境与参数：Apple M2、16GB 内存、macOS 26；CPU/NEON 推理，关闭 Metal，`n_gpu_layers = 0`；`n_ctx = 4096`、`n_batch = 512`、6 个 CPU 线程；输入上限 1500 字符、App 最大输出 1024 tokens；`temperature = 0.7`、`top_p = 0.6`、`top_k = 20`、`repetition_penalty = 1.05`、固定 seed 42。每款模型连续执行 20 次中英双向翻译，并完成 1.25-bit → 2-bit → 1.25-bit 卸载切换。

| 模型 | 文件体积 | 加载 | 首 token | 持续生成 | 进程 RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hy-MT2 1.8B 1.25-bit 轻量版 | 约 440 MB | 0.264 秒 | 0.60–1.02 秒 | 32–61 tokens/s | 824–859 MB |
| Hy-MT2 1.8B 2-bit 均衡版 | 约 573 MB | 0.976 秒 | 0.25–0.50 秒 | 11.85–25 tokens/s | 1.20–1.29 GB |

20 轮后没有观察到逐轮持续内存增长，峰值低于 1.5 GiB；加载、生成、取消和卸载流程另通过 Address Sanitizer。42 条多语言与格式保持样例在两款模型上共执行 84 次结构检查，均得到非空且无特殊 token/提示词泄漏的输出；这项结构检查不等同于人工语义质量评估。翻译质量仍与语言、文本类型和量化精度相关，2-bit 并不保证在每个输入上都优于 1.25-bit；正式选择建议以自己的常用文本实测为准。可审计门禁代码见 [`Runtime/LlamaRuntime/Tests/RuntimeGate.cpp`](Runtime/LlamaRuntime/Tests/RuntimeGate.cpp)。

## 从源码构建 macOS App

App 最低支持 macOS 15；从源码构建仍需要带 macOS 26 SDK 的 Xcode（用于编译受可用性保护的 Liquid Glass 分支）、XcodeGen 与 Apple Silicon Mac：

```bash
brew install xcodegen
./script/build_and_run.sh --verify
```

脚本只为当前项目设置 `DEVELOPER_DIR`，不会修改系统全局 `xcode-select`。默认使用 `/Applications/Xcode-beta.app/Contents/Developer`，可在脚本调用前覆盖 `DEVELOPER_DIR`。

## CLI 与本地 API

CLI 仍会按机器内存选择推荐的 Gemma 档位，并在首次运行时下载模型；GUI App 则始终由用户明确选择模型。

```bash
git clone https://github.com/Rand01ph/gemma-trans && cd gemma-trans
# MLX 的 Metal 着色器需要 xcodebuild（首次如提示缺 Metal 工具链：xcodebuild -downloadComponent MetalToolchain）
xcodebuild -scheme gemma-trans-cli -destination 'platform=macOS' -skipMacroValidation -derivedDataPath .build-cli build
.build-cli/Build/Products/Debug/gemma-trans-cli serve
# CLI 首次运行自动下载推荐模型 → Model ready. Listening on http://127.0.0.1:8765
```

国内网络可用镜像：启动前 `export HF_ENDPOINT=https://hf-mirror.com`。`gemma-trans-cli spike` 跑一次最小验证。

### 调用

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

1. 安装并运行 GemmaTrans App，确保已经下载并启用一个模型。
2. 在 Finder 中双击 `popclip/GemmaTrans.popclipext` 目录，PopClip 会提示安装。
3. 任意 App 中选中文字，点击 PopClip 弹条中的 GemmaTrans 图标；插件会调用系统服务，在 GemmaTrans 可滚动的多行浮窗中流式显示译文。

内置 PopClip 插件不再使用单行且最多预览 160 字符的 `show-result`，也不依赖本地 API 开关。若要通过 PopClip 的其他扩展测试 API，仍可将任何接受 `/v1/chat/completions` 请求格式的扩展指向 `http://127.0.0.1:8765/v1`（API key 随意填）。

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

- 启动后显示主窗口与 menu bar 状态项；尚未选择模型时会引导进入模型设置，不会联网或自动下载
- **三种译法**（均无需辅助功能权限）：
  - 主窗口里粘贴/输入文字 → 点「翻译」流式显示译文
  - 任意 app 选中文字 → 按 `⌥⌘T` 一键翻译选中内容，**无需先复制**；也可从「服务」菜单点「Translate with GemmaTrans」
    - 这是 macOS「服务」快捷键，默认 `⌥⌘T`。macOS 不一定会自动启用声明的默认值——若按了没反应，去 系统设置 › 键盘 › 键盘快捷键 › 服务 › 文本，勾选并确认 Translate with GemmaTrans 的快捷键（一次性，之后长期生效；也可在这里改键）
  - 复制文字后按 `⌥D` → 翻译剪贴板内容（浮窗流式显示，Esc 关闭，可复制、朗读或固定位置）
- 菜单“设置…”可改外观、目标语言、译文字号、API 端口和剪贴板热键
- 设置"性能"区默认按机器内存自动配置 KV cache 与输入上限（加载时还会按当前可用内存降档），也可手动覆盖

## 架构

```
GemmaTransKit     核心库：MLX-Swift 引擎封装、语言检测（NaturalLanguage）、提示词、按内存自动调优
GemmaTransServer  HTTP 层：FlyingFox，/translate + /v1/chat/completions + SSE
gemma-trans-cli   命令行：spike / serve
LlamaRuntime      两款策展 Hy-MT2 GGUF 的静态 CPU/NEON 后端；不开放任意 GGUF 加载
```

## 许可证与商业版本

除另有声明的第三方内容外，本仓库公开的 GemmaTrans 源代码与随附文档采用 [MIT License](LICENSE)。你可以在保留版权声明与许可证的前提下使用、修改、分发和商业使用这些内容，完整条款以许可证原文为准。

未来如提供独立开发、单独发布且未以 MIT 授权的闭源 Pro 模块，将采用随该模块提供的独立商业许可。付费功能的推出不会收回或限制已按 MIT 发布的代码所授予的权利；本说明也不代表 Pro 功能已经上线。

第三方依赖、运行时中的上游代码（包括补丁中的第三方内容）和模型权重保留各自的版权声明与许可证，不因本项目采用 MIT 而改变授权。App 安装包不内置模型权重，模型在使用时从上游下载；下载方式不免除适用的模型许可义务。来源与许可证入口见 [第三方声明](THIRD_PARTY_NOTICES.md)。

## 发布

- [CHANGELOG.md](CHANGELOG.md)：版本变更记录
- [docs/release-notes-2.0.md](docs/release-notes-2.0.md)：GemmaTrans 2.0 发布文案与升级说明
- [docs/release-notes-2.1.md](docs/release-notes-2.1.md)：GemmaTrans 2.1 发布文案、测试重点与升级说明
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)：定制运行时来源与第三方许可证索引
- [docs/social-launch-2.0.md](docs/social-launch-2.0.md)：小红书首发、连续宣传选题与 V2EX 技术复盘稿
- [docs/store-listing.md](docs/store-listing.md)：Mac App Store 描述、审核备注与提审清单
- [docs/releasing.md](docs/releasing.md)：版本、Actions Secrets、签名、公证与 MAS 发布步骤
- `Scripts/release.sh`：Developer ID 签名、公证并生成 ZIP/DMG
- `Scripts/release-mas.sh`：使用 Xcode 自带工具归档、导出及可选上传 MAS 包，不依赖第三方 `asc` CLI
