# 推理引擎迁移设计：LiteRT-LM → MLX-Swift

日期：2026-06-11
状态：已确认（方案 A：直接替换，退役 LiteRT）

## 背景与动机

用户决策只主打 macOS + iOS。MLX 是 Apple 自家框架，统一内存原生优化：

- 直击实际痛点：16GB 机器内存压力下 LiteRT 反复出现 `mldrift buffer allocation failed`
- 4-bit 量化 E4B 约 2.3GB（现 .litertlm 3.4GB），内存预算更友好
- 纯版本化 SPM 依赖，退役 LiteRT 的 unsafeFlags/vendor/bootstrap 整套 hack
- iOS 同一套库（MLXLLM 支持 iOS），为 M4 iOS app 铺路

## 已核实事实（2026-06-11，源码级）

- `ml-explore/mlx-swift-lm`（from 3.31.3，产品 `MLXLLM`/`MLXLMCommon`）一等支持 Gemma 4：`Gemma4Model`、`LLMModelFactory` 注册 `"gemma4"`
- 内置注册表：`LLMRegistry.gemma4_e4b_it_4bit` → `mlx-community/gemma-4-e4b-it-4bit`；另有 `gemma4_e2b_it_4bit`
- `ChatSession.streamResponse(to:)` 提供流式生成
- 模型经 HuggingFace Hub 自动下载（HubApi），支持进度回调

## 设计

### 改动面（协议 `TranslationService` 外零变化）

| 模块 | 改动 |
|------|------|
| Package.swift | 移除 `Vendor/LiteRT-LM` path 依赖 → `mlx-swift-lm` from 3.31.3 |
| Scripts/bootstrap.sh、Vendor 机制 | 删除（连同 .gitignore 的 Vendor/ 行保留无害） |
| TranslationEngine.swift | 内部重写：MLX 加载 + ChatSession 流式；串行队列/去抖/截断逻辑原样 |
| EngineTuning | 档位输出改为（模型变体, maxTokens, maxInputChars）：≥16GB 充裕 → e4b-4bit；<16GB 或压力降档 → e2b-4bit。纯函数+测试结构不变 |
| EngineController | 状态增加下载进度（"模型下载中 N%"） |
| SettingsView | 模型区退役"路径+选择文件+下载链接+bookmark"，改显示变体与下载状态 |
| AppSettings | modelPath/modelBookmark 字段及 bookmark resolve 逻辑删除 |
| gemma-trans-cli | spike/serve 改 MLX |
| 测试 | EngineIntegrationTests：enabled-if 改为 Hub 缓存存在；其余单测不动 |
| 不变 | HTTP API、PopClip、浮窗、热键、SelectionReader、LanguageDetector、单实例守卫 |

### 模型下载

- Hub 自动下载到应用可写目录（sandbox 容器内 Documents/huggingface），无需用户手动操作
- menu bar/设置页显示下载进度；失败可重试
- 国内镜像：`HF_ENDPOINT` 环境变量（README 说明）

### 发布影响

- 已上传的 LiteRT 版 build 1/2 作废不提审；MLX 版验证后出 **build 3**
- 商店描述/审核备注模型大小 4GB → 约 2.3GB，下载方式改"应用内自动下载"
- 直分包重出（release.sh 流程不变）

### Spike 先行（中止条件）

CLI 实测 e4b-4bit：① 流式翻译跑通；② 同机对比 LiteRT 记录加载时长/生成速度/内存压力表现。若 MLX 在本机表现明显劣于 LiteRT（生成速度 < 一半）或不可用 → 停止迁移并上报复盘。

## 不做（YAGNI）

双后端共存/运行时切换；社区 gemma-4-swift-mlx 包（官方已覆盖）；iOS app 本体（独立 spec）；模型变体用户自选 UI（自动调优决定，手动模式仅 maxTokens/输入上限）。
