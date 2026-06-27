# Plan A — Hunyuan-on-MLX-Swift Spike（决策门）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 验证腾讯混元 dense 架构（Hy-MT2-1.8B）能否在 Swift 版 MLX 上加载并产出合理翻译，作为 Hy-MT2 接入的决策门。

**Architecture:** 在 `GemmaTransKit` 内移植 `Hunyuan.swift`（混元 dense，含 CLA 跨层 KV 共享），
通过 `LLMTypeRegistry.shared.registerModelType("hunyuan_v1_dense", …)` 注册进 MLXLLM 的类型表；
复用现有 `TranslationEngine` 加载路径（按 config.json 的 `model_type` 分发）加载本地快照，跑一句翻译人工核对。

**Tech Stack:** Swift 6 · MLX-Swift（mlx-swift-lm `MLXLLM`/`MLXLMCommon`）· Python mlx-lm 参考实现。

## Global Constraints

- 本计划是 **spike**，非交付特性：步骤偏「探索+验证」，不强求严格 TDD bite-size。
- 不修改 `.build/checkouts` 下的依赖源码（不 fork）；Hunyuan 实现落在 `Sources/GemmaTransKit/Models/`。
- 外网下载（权重/参考代码）一律交用户执行，不自行 curl（见用户 curl 全局禁用约束）；本机加载/推理可跑。
- 决策门：**GATE 不过 → Hy-MT2 从策展表撤下，Plan B 退化为 Gemma-only**，本 spike 成果（Hunyuan.swift）保留待后续。
- 加载分发机制已确认：`LLMModelFactory.loadContainer` 读 `baseConfig.modelType` → `typeRegistry.createModel`
  （`.build/checkouts/mlx-swift-lm/Libraries/MLXLLM/LLMModelFactory.swift:522`）。

---

### Task 1: 取得参考实现与权重，确认加载入口走共享类型表

**Files:**
- 无代码改动（调研 + 准备）

- [ ] **Step 1: 让用户下载 Python mlx-lm 的混元参考实现**

请用户在本机执行（外网下载交用户）：
```bash
# Python mlx-lm 仓库里 model_type=hunyuan_v1_dense 的实现文件
# 通常位于 mlx_lm/models/hunyuan_v1_dense.py（若改名，按 model_type grep 定位）
pip download mlx-lm --no-deps -d /tmp/mlxlm-src  # 或 git clone ml-explore/mlx-lm
```
产出：`hunyuan_v1_dense.py`（移植蓝本）路径。

- [ ] **Step 2: 让用户下载 4bit 权重到工程默认模型目录**

```bash
# 走 app 自身下载器更省事：见 Task 4 的 smoke；此处也可让用户用 hf/modelscope CLI 手取
# 目标 repo：mlx-community/Hy-MT2-1.8B-4bit
```
产出：本地快照目录（含 `config.json` / `*.safetensors` / `tokenizer*.json`）。

- [ ] **Step 3: 确认 TranslationEngine 的加载路径最终经过 `LLMTypeRegistry.shared`**

Read：`Sources/GemmaTransKit/TranslationEngine.swift:98-121`（`loadModelContainer(from:using:)`）与
`.build/checkouts/mlx-swift-lm/Libraries/MLXLLM/LLMModelFactory.swift:500-550`。
确认：本地快照加载按 `config.json.model_type` 调 `typeRegistry.createModel`，且该 registry 即
`LLMTypeRegistry.shared`。若该 helper 走的是另一个 registry 实例，记录其获取方式（Task 3 注册要注册到同一实例）。
Expected：确认注册目标 registry 实例，无代码改动。

---

### Task 2: 移植 Hunyuan dense 架构为 Swift

**Files:**
- Create: `Sources/GemmaTransKit/Models/Hunyuan.swift`

**Interfaces:**
- Produces: `public class HunyuanModel: Module, LLMModel, KVCacheDimensionProvider`（供 Task 3 注册）；
  `public struct HunyuanConfiguration: Codable, Sendable`（映射 config.json）。

- [ ] **Step 1: 按 config.json 写 `HunyuanConfiguration`**

对照 `mlx-community/Hy-MT2-1.8B-4bit/config.json` 字段（`hidden_size=2048`、`num_hidden_layers=32`、
`cla_share_factor`、`dense_list`、`im_start_id`/`im_end_id`、`quantization{group_size,bits}` 等），
仿 `Sources/...` 既有模型与 `adding-model.md`（`.build/checkouts/mlx-swift-lm/Libraries/MLXLLM/Documentation.docc/adding-model.md`）的 Configuration 模式写 Codable 结构。

- [ ] **Step 2: 移植模型主体（attention/mlp/decoder layer/inner/top-level）**

以 `hunyuan_v1_dense.py` 为蓝本逐层转 Swift MLX，参照同库已有 Llama/Qwen2 Swift 实现的算子用法
（`.build/checkouts/mlx-swift-lm/Libraries/MLXLLM/Models/Llama.swift`、`Qwen2.swift`）。
**重点踩坑项**：`cla_share_factor`（每 N 层共享 KV 投影/缓存）、`dense_list`、QK-Norm（若有）、
rope 配置。顶层类签名按 `adding-model.md`：
```swift
public class HunyuanModel: Module, LLMModel, KVCacheDimensionProvider {
    public let kvHeads: [Int]
    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray { /* ... */ }
}
```

- [ ] **Step 3: 编译通过（仅类型/算子层面，不验证数值）**

Run: `swift build --target GemmaTransKit`
Expected: 编译成功（数值正确性留到 Task 4 真实加载验证）。

---

### Task 3: 注册自定义类型并暴露加载入口

**Files:**
- Create/Modify: `Sources/GemmaTransKit/Models/HunyuanRegistration.swift`（或并入引擎启动路径）

**Interfaces:**
- Consumes: `HunyuanModel`/`HunyuanConfiguration`（Task 2）。
- Produces: `public func registerHunyuanIfNeeded() async`（幂等注册到 Task 1 确认的 registry 实例）。

- [ ] **Step 1: 写幂等注册函数**

```swift
import MLXLLM
import MLXLMCommon

private actor HunyuanReg { static let shared = HunyuanReg(); var done = false }

public func registerHunyuanIfNeeded() async {
    guard await !HunyuanReg.shared.done else { return }
    await LLMTypeRegistry.shared.registerModelType("hunyuan_v1_dense") { data in
        let config = try JSONDecoder().decode(HunyuanConfiguration.self, from: data)
        return HunyuanModel(config)
    }
    await HunyuanReg.shared.markDone()
}
```
（`registerModelType` 签名见 `.build/checkouts/mlx-swift-lm/Libraries/MLXLMCommon/Registries/ModelTypeRegistry.swift:20`：
`(_ type: String, creator: @escaping (Data) throws -> T)`。若 Task 1 确认目标 registry 非 `LLMTypeRegistry.shared`，改注册到该实例。）

- [ ] **Step 2: 在引擎加载前调用注册**

Modify `TranslationEngine.load()`：在 `loadModelContainer(from:)` 之前 `await registerHunyuanIfNeeded()`
（仅当目标模型 family 为混元时调用；spike 阶段可无条件调用，无副作用）。

- [ ] **Step 3: 编译通过**

Run: `swift build --target GemmaTransKit`
Expected: 成功。

---

### Task 4: 真实加载 + 翻译 smoke（GATE 验证）

**Files:**
- Create: `Sources/gemma-trans-cli/` 下临时 spike 子命令，或一次性测试 `Tests/GemmaTransKitTests/HunyuanSpikeTests.swift`（标记手动/需真权重）

- [ ] **Step 1: 写一次性加载+翻译 smoke**

用 CLI 子命令或手动测试：注册 Hunyuan → 用引擎以 `mlx-community/Hy-MT2-1.8B-4bit` 本地快照加载 →
对一句中文（如「今天天气很好，我们去公园散步吧。」）请求英译 → 打印输出。

- [ ] **Step 2: 运行并人工核对（GATE）**

Run: 执行该 smoke（需 GPU/前台，参考 macOS 现有运行方式）。
Expected / GATE 判据（全部满足才算过）：
1. 加载不抛 `unsupportedModelType`；
2. 生成不崩溃、能流式出 token；
3. 输出是**连贯、正确的英文翻译**（非乱码/复读/串语种）。

- [ ] **Step 3: 记录结论**

- **过** → 在 spec 标记决策门通过；Plan B 保留 Hy-MT2 两条目；Plan C（Hy-MT2 prompt 接入）启动。
- **不过** → 记录失败现象（加载错误/数值乱码/CLA 行为不符）；Plan B 切 Gemma-only；保留 `Hunyuan.swift` 备后续。

- [ ] **Step 4: 提交 spike 成果**

```bash
git add Sources/GemmaTransKit/Models/ docs/superpowers/plans/2026-06-27-planA-hunyuan-spike.md
git commit -m "spike: 混元 dense 架构 Swift 移植 + 加载验证（决策门）"
```

---

## Self-Review

- 覆盖 spec 阶段 0（Hunyuan spike 决策门）全部要点：移植、注册、加载、翻译验证、GATE 降级。
- 无 TODO 占位；外网下载步骤明确交用户执行。
- 类型一致：`HunyuanModel`/`HunyuanConfiguration`/`registerHunyuanIfNeeded` 跨 Task 一致。
- 已知不确定点（CLA 数值正确性、目标 registry 实例）已在步骤内显式标注为验证项，符合 spike 性质。
