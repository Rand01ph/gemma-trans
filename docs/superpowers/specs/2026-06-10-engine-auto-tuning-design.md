# GemmaTrans 引擎参数自动调优设计

日期：2026-06-10
状态：已确认（方案 A：静态分档 + 加载时压力降档）

## 背景

KV cache（`maxNumTokens`）与输入上限（`maxInputChars`）目前硬编码（2048/1500，按 16GB M2 手调）。
真实故障（2026-06-10 PopClip 500）表明：故障变量不仅是物理内存大小，还有**加载/生成时刻的可用内存**。
目标：按机器配置自动推导这两个参数，强机器吃满能力，弱机器/高压力时刻自动保守。

## 设计

### EngineTuning（GemmaTransKit，纯函数，可单测）

```swift
public struct EngineTuning: Sendable, Equatable {
    public let maxNumTokens: Int
    public let maxInputChars: Int
}
```

`EngineTuning.recommended(physicalMemory: UInt64, availableMemory: UInt64, modelFileSize: UInt64) -> EngineTuning`

1. 按物理内存定基准档：≥48GB → 8192/6000；≥32GB → 4096/3000；≥16GB → 2048/1500；<16GB → 1024/700
2. 压力降档：`availableMemory < modelFileSize + 4GB 工作余量` 时降一档（最低档不再降）
3. 档位表为内部常量数组，降档即取下一行

### SystemMemory（GemmaTransKit）

- `physical()`：`ProcessInfo.processInfo.physicalMemory`
- `available()`：`host_statistics64` 的 free + inactive 页 × 页大小（near-realtime，无需特权）

### 接入点

- `TranslationEngine.load()`：settings 为自动模式时调用 `EngineTuning.recommended`（模型文件大小用 `FileManager` 取），结果存入 `resolvedTuning`（actor 属性），`GTLog.info` 记录所选档位与依据；`translate()` 的截断改用 `resolvedTuning.maxInputChars`
- `AppSettings`：新增 `autoTuning: Bool = true`；手动模式沿用 `maxInputChars` 并新增 `manualMaxNumTokens: Int = 2048`
- 设置页新增"性能"区：自动开关（默认开）+ 当前生效值展示；关闭时显示两个数字输入框

### 错误处理

- 可用内存读取失败 → 视为充足（不降档），仅日志记录；行为退化为方案 B
- 模型文件大小读取失败 → 按 4GB 估算

### 测试

- 纯函数表测：四档边界（47.9/48、31.9/32、15.9/16GB）
- 降档测：16GB 物理 + 2GB 可用 → 1024/700
- 最低档不下穿：8GB 物理 + 1GB 可用 → 仍 1024/700
- 手动模式优先：autoTuning=false 时用手动值
- 现有引擎集成测试继续通过（本机 16GB 空闲时应选 2048/1500，行为不变）

## 不做（YAGNI）

运行时动态降档重载（方案 C，远期）；按模型规格（E2B/12B）差异化档表；GPU 型号检测。
