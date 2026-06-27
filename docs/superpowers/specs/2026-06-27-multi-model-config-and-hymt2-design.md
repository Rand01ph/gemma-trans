# 多模型下载/切换 + Hy-MT2 接入 设计

日期：2026-06-27
状态：设计已确认，待排实现计划

## 背景与动机

当前 app 只有 Gemma 两档（E4B 4bit ≈4.9GB / E2B 3.6GB），由 `EngineTuning.recommended`
按内存自动选，模型标识写死在 `ModelVariant` enum 里，仓库名/注册表配置/prompt 全 key 在它上面。

有用户建议接入 **Hy-MT2-1.8B**（腾讯混元翻译模型 MT2，2026-05-21 开源，翻译专用，
33 语言）。同时模型数量变多，需要配置页支持**下载与切换多模型**。

### Hy-MT2 可行性调研结论（关键约束）

- ✅ MLX 格式权重存在：`mlx-community/Hy-MT2-1.8B-4bit`(~1GB)、`-8bit`(~1.9GB)、`-bf16`(~3.58GB)；
  ModelScope 国内源同步开源（`ModelDownloader` 双源逻辑天然可下）。
- ❌ **Swift 版 MLXLLM 不支持混元架构**：config 架构为 `HunYuanDenseV1ForCausalLM`
  / `model_type: hunyuan_v1_dense`，带 `cla_share_factor`（跨层 KV 共享）、`dense_list`
  等非标准结构。`mlx-swift-lm` 的 `Models/` 下 50+ 架构无 Hunyuan，grep 零命中。
- ✅ **可在 app 侧补，无需 fork 依赖**：`MLXLMCommon` 的 `ModelTypeRegistry`（actor）
  有公开 `registerModelType(...)`。在 Kit 内实现 `Hunyuan.swift` 并注册即可加载。

→ 故 Hy-MT2 接入的真实工作量 = **把混元 dense 架构（含 CLA）从 Python mlx-lm 移植成
Swift MLX**。有参考实现（mlx-community 权重即 Python mlx-lm 转出），属移植+验证，非从零设计；
但 CLA 等非标准结构有踩坑风险，列为**风险前置的 spike 决策门**。

## 已确认的产品决策

- **平台**：macOS 优先；架构（catalog、引擎、下载器）落在 `GemmaTransKit` 共享，iOS 可复用，
  iOS UI 留后续 spec。
- **模型目录**：策展固定表，共 5 项：
  - `Auto`（按内存选 Gemma，现有行为，**默认**）
  - `Gemma E4B 4bit`、`Gemma E2B 4bit`
  - `Hy-MT2-1.8B 4bit`、`Hy-MT2-1.8B 8bit`
- **默认不变**：`Auto` 仍是默认，不动存量用户；Hy-MT2 为 opt-in（移植稳定性验证前不当默认）。
- **存储与切换**：多个模型并存于磁盘，配置页一键设为活跃（卸旧载新）；提供删除管理，活跃中禁删。
- **切换守卫**：引擎正在翻译/加载中，**或 API server 运行中**，禁止切换（UI 置灰 + 提示）。
- **选具体模型** = 复用现成 `tuningOverride` 强制 variant，`maxTokens/maxInputChars` 仍按内存档缩放。

## 分阶段（风险从高到低）

合成一个 spec，但内部按风险分阶段，第 0 阶段为决策门——整个 feature 最不确定的是
「混元架构能否在 Swift MLX 上跑对」，不该 UI 全做完才发现跑不通。

| 阶段 | 内容 | 性质 |
|------|------|------|
| **0. Hunyuan spike（决策门）** | Kit 内写 `Hunyuan.swift`（移植混元 dense，含 CLA），`registerModelType("hunyuan_v1_dense", …)`，加载 `Hy-MT2-1.8B-4bit` 跑通一句翻译并人工核对输出合理 | **GATE**：跑不通 → Hy-MT2 从策展表撤下，feature 退化为「Gemma-only 多模型基础设施」（仍有价值），不阻塞其余阶段 |
| **1. 模型抽象重构** | 把 `ModelVariant`/tuning/repo/prompt 从「写死 Gemma」解耦，引入 `ModelCatalog` | 基础设施 |
| **2. 多模型存储 + 切换** | 下载器支持磁盘 N 模型；settings 存活跃选择；引擎运行时切换；删除管理 + 切换守卫 | 基础设施 |
| **3. macOS 配置页 UI** | `SettingsView` 模型列表：未下载/下载中(进度)/已下/活跃中 + 下载/设为活跃/删除 | UI |
| **4. Hy-MT2 prompt 接入** | 按 family 拆 `PromptBuilder`，接 Hy-MT2 翻译指令格式；4bit/8bit 挂表 | 集成 |

## 模型抽象重构（阶段 1，最核心）

现状 `ModelVariant`（`Sources/GemmaTransKit/EngineTuning.swift`）是 enum 且语义绑死 Gemma：
`estimatedBytes`、`TranslationEngine.load()` 里 `switch variant → LLMRegistry.gemma4_*`、
`repoName(for:)`、`PromptBuilder` 都 key 在它上面。

改为**策展数据表 `ModelCatalog`**，每条目带：

- `id`：稳定标识，存进 settings（如 `gemma-e4b-4bit` / `hymt2-4bit` / `hymt2-8bit`）
- `repo`：HF/ModelScope 仓库名（如 `mlx-community/Hy-MT2-1.8B-4bit`）
- `family`：`.gemma` / `.hunyuanMT2`——决定 prompt 策略与是否需注册自定义架构
- `estimatedBytes`、`displayName`、默认 `maxTokens` / `maxInputChars`
- `requiresCustomType: Bool`：Hy-MT2=true，加载前先 `registerModelType`

`AppSettings` 新增 `selectedModelID: String`（`"auto"` 或某 catalog id）。`Auto` 仍走
`EngineTuning.recommended`。变体不变量（variant↔repo）由 catalog 单点持有，消除当前散落
多处的 `repoName`/`switch`。`ModelVariant` 既有 Gemma 两例保留（Auto/Gemma 路径不变），
新 family 的具体模型由 catalog 描述，不强行塞进同一 enum 语义。

## 存储、切换与下载（阶段 2）

- **下载器**：`ModelDownloader` 已按 repo 泛化、双源齐全，几乎不用改（Hy-MT2 在 ModelScope
  亦有）。
- **磁盘布局**：沿用 `snapshotDirectory(base, repo)`，每模型一目录、并存无冲突。
- **切换**：`EngineController`(macOS)/`EngineHolder`(iOS) 加 `switchModel(id)` →
  引擎 `model = nil` + 重新 `load(新 repo/override)`；切换期间 UI 走 `.loading`。
- **切换守卫**：`switchModel` 在以下任一状态拒绝并提示——引擎 `isGenerating`、
  正在 `loading`、或 `apiStatus == .running`。UI 对应置灰切换控件。
- **管理**：扫描 base 目录列出已下模型 + 体积；删除入口（删目录），活跃中模型禁删。

## Hy-MT2 集成（阶段 0 + 4）

- **架构移植**（阶段 0）：参考 Python mlx-lm 的 hunyuan 实现 + config 字段
  （`cla_share_factor`、`dense_list`、`im_start/end_id`）写 Swift 版，
  `LLMTypeRegistry.shared.registerModelType` 注册。**真正的工程风险点**，spike 先行。
- **Prompt**（阶段 4）：`PromptBuilder` 按 family 分流。Hy-MT2 有自身翻译指令格式
  （33 语言、im_start/end 模板），对齐其 `tokenizer_config.json` 的 chat template；
  Gemma 路径保持不变。

## 测试

- 纯函数层（`ModelCatalog` 查表、settings id 解析、tuning 推导、切换守卫判定）全单测，
  沿用现有 `GemmaTransKitTests` 风格。
- Hunyuan 移植：spike 阶段人工验证输出；后续加「加载+短翻译」集成 smoke（需真权重，标记手动）。
- 下载器既有测试不回归。

## 非目标（YAGNI）

- 不做任意 HF/ModelScope 仓库手填（架构兼容性不可控）。
- 不做 Qwen3 等额外模型（本期策展表只 Gemma + Hy-MT2）。
- 不做 iOS 配置页 UI（架构留口，UI 后续 spec）。
- 不做后台自动切换/自动清理磁盘（删除为手动）。
- 不做 GGUF / llama.cpp 推理栈（沿用 MLX）。

## 未决/实现期确认

- 阶段 0 spike 若证明 CLA 移植成本过高或输出不达标，按决策门降级为 Gemma-only。
- Hy-MT2 chat template 的确切 system/user 分段，实现期读 `tokenizer_config.json` 对齐。
