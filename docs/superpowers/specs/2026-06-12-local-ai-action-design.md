# GemmaTrans「本地 AI 处理」节点设计（v2 主线 · 待评审）

日期：2026-06-12
状态：已确认，范围 **B（带任务库 UI）**，执行中；端到端真机跑通（2026-06-13，
`task=builtin.courier load=4.1s process=1.2s`）

**已评估否决的方向（避免重复绕回）**：
- **IdentityLookup / ILMessageFilterExtension 自动处理短信** ❌：只能返回分类枚举
  （allow/junk/transaction），无创建待办/调模型/触发动作的接口；内容锁死扩展内
  （不能联网、不能写共享容器）；扩展内存连 1.7MB Core ML 都崩，跑不了 Gemma；
  只覆盖陌生号 SMS，联系人短信与所有 iMessage 不经过。正道仅"垃圾短信分类"
  （需 KB 级小模型，另一个产品）。结论：快捷指令是「短信→动作」唯一通道。
- **触发器配置真相（iOS 18/26 真机实测）**：「信息」触发器**必须填有效筛选条件
  （信息包含关键词）才触发**，发件人/内容全留空不工作（空发件人条件致失效）。
  之前调研代理给的"可全留空=任何人"在 iOS 18/26 错误，已纠正指引文档。

**配置门槛优化（待办）**：手动配置坑多（空发件人/变量选错/过滤逻辑/关键词必填，
真机连踩四坑才通）。方案：把动作链（本地AI处理→if含无停→添加提醒）抽成普通快捷指令，
经 iCloud 链接一键导入（自动化触发器无法打包，用户仍需自建「信息」触发器 + 关键词 +
立即运行，但最坑的变量/if/字段全省）。链接须从真机分享生成。

**范围 B 补充设计（任务库与 Intent 的衔接）**：
- 自定义任务模型 `ProcessTask`（id/name/instruction，Codable）与 `ProcessTaskStore`
  放 **Kit**（UserDefaults suite 可注入 → macOS 可单测；iOS 传 App Group suite，
  intent 与 UI 两进程共享）
- Intent 的任务参数不用静态 AppEnum，改 **`AppEntity`（ProcessTaskEntity）**：
  query 返回 内置预设 + 任务库自定义任务——用户在任务库存的任务直接出现在
  快捷指令的参数下拉里，这是范围 B 的核心价值
- 任务库 UI：TranslatorView 工具栏入口 → 列表（内置区只读 + 自定义区增删改）→
  编辑页（名称 + 指令 TextEditor + 试运行：样例输入 → 前台 GPU 引擎流式出结果）
前置：[2026-06-11-ios-app-design.md](2026-06-11-ios-app-design.md)（已验证的通路事实：
App Intent 后台 6GB 额度 / CPU 推理短文本 0.3s / GPU 仅前台 / 输出可回传快捷指令）

## 定位

把已打通的「App Intent 后台 → 本地 Gemma」通路泛化成 **iOS 快捷指令生态里的一个
本地大模型处理节点**：不联网、不要 API key、文本不离开设备。翻译是它的第一个特例；
本设计把 prompt 开放为参数，让任意「文本 + 指令」任务都能跑。

首发验证场景：**快递短信 → 提醒事项**（用户指定）。

## 用户故事

1. 一次性配置（约 2 分钟，提供图文指引）：
   快捷指令 app → 自动化 → 「当收到信息」（信息内容包含「取件」或「快递」）→
   获取信息内容 → GemmaTrans「本地 AI 处理」（预设：快递取件提取）→
   「添加提醒事项」（标题 = 上一步输出，列表 = 取快递，提醒时间可选今天 20:00）
2. 此后收到快递短信几秒内，提醒事项自动出现：
   `取件: 丰巢 3 号柜 · 码 8821 · 今天 21 点前`
   全程后台、零打开 app、零联网。
3. 已知边界（如实告知用户）：短信**无法自动标记已读**（iOS 不开放，需手动）；
   自动化触发器只能读到**触发那条**短信的内容，不能扫历史短信。

## Intent 设计

新增 `ProcessTextIntent`（与 TranslateIntent 并列，AppiOS/GemmaTransiOS/）：

```swift
struct ProcessTextIntent: AppIntent {
    static let title: LocalizedStringResource = "本地 AI 处理"
    static let openAppWhenRun = false        // 后台 CPU，不跳转（短文本 0.3s 够用）

    @Parameter(title: "文本") var text: String
    @Parameter(title: "任务") var task: ProcessTask          // AppEnum 预设
    @Parameter(title: "自定义指令") var instruction: String?  // task == .custom 时用

    func perform() async throws
        -> some IntentResult & ReturnsValue<String> & ProvidesDialog
}
```

- **`ReturnsValue<String>` 是灵魂**：输出作为变量回传快捷指令，可直接喂给系统的
  「添加提醒事项 / 存入备忘录 / 发送通知」等后续动作——自动化由用户拼装，我们不造待办轮子
- dialog 同时原地弹一份结果（手动触发场景可见）
- 执行体复用 TranslateIntent 模式：自建临时引擎 + useCPU + E2B 档；
  输入上限 700 字符（短信/段落级；超长截断并在 dialog 注明）

### 预设任务（ProcessTask: AppEnum）

| case | 指令（prompt 要点） | 输出契约 |
|---|---|---|
| `courierPickup` 快递取件提取 | 从短信提取取件信息 | 单行：`取件: <地点> · 码 <取件码> · <时限>`；缺项跳过；非快递短信输出 `无` |
| `summarize` 要点总结 | 三句话以内总结 | 纯文本，无前缀 |
| `custom` 自定义 | 取 `instruction` 参数原文 | 由指令自定 |

**输出格式刻意用单行竖点文本、不用 JSON**——E2B(2B) 输出 JSON 不稳定，简单格式
它拿手，且提醒事项标题本来就要一行人话。`无` 约定让快捷指令可加「如果=无则停止」分支。

### prompt 结构（Kit）

PromptBuilder 泛化（翻译路径不动）：

```
system: You are a text processing engine. Follow the instruction exactly.
        Output only the result, no explanation. Reply in the language of the input
        unless the instruction says otherwise.
user:   <instruction>\n\n<text>
```

预设指令全文存 Kit（中文写，目标输出也是中文），上架前用真实快递短信
（丰巢/菜鸟/京东/邮政至少各 2 条）迭代验收：提取正确率 ≥ 9/10 才算过。

### AppShortcuts

`GemmaTransShortcuts` 追加一条 AppShortcut（短语「用 GemmaTrans 处理」），
让「本地 AI 处理」在快捷指令库/Spotlight 即搜即用。

## Kit 改动

- `PromptBuilder`：加 `processSystemPrompt` 与 `processUserPrompt(text:instruction:)`
- `TranslationEngine`：加 `process(_ text: String, instruction: String) async throws -> String`
  （一次性会话、复用串行队列与 maxTokens；不走 LanguageDetector）
- 预设指令表 `ProcessPresets`（含 courierPickup/summarize 的指令全文，可单测锁定）

## 交付物

1. Kit：process 通路 + 预设表（单测：prompt 拼装、预设表完整性）
2. iOS：ProcessTextIntent + AppEnum + AppShortcut（构建验证）
3. 真机验收：手动跑通快递短信样例 ≥9/10；配置完整自动化端到端一次
4. 文档：`docs/shortcuts-guide.md` 图文指引（自动化配置步骤 + 已读限制说明），
   设置页「系统集成」区加入口链接

## 范围分叉（评审点）

- **A 最薄版（推荐）**：上述全部，app UI 零改动。预估一个下午 + prompt 调校
- **B 带任务库 UI**：app 内增「任务库」页（增删改自定义指令、试运行、保存常用）。
  体验完整但工作量 ×3；建议 A 验证场景成立后再补
- 共同 YAGNI：读取历史短信（系统不允许）、自动标已读（同）、JSON 结构化输出、
  云端兜底（另见 v2 候选）、macOS 端同款 intent（后续自然延伸）

## 风险

| 风险 | 缓解 |
|---|---|
| E2B 提取正确率不达标 | prompt 迭代 + few-shot 示例内嵌；仍不行则该预设降级为「摘要式」输出 |
| 自动化配置门槛劝退 | 图文指引 + 后续可分发 .shortcut 模板文件一键导入 |
| 后台 intent 冷加载 3s 在自动化里被感知 | 自动化是异步无人等待场景，3s 无感；保留说明 |
| 快捷指令「当收到信息」触发器需要 iOS 17+ 个人自动化且「立即运行」开关 | 指引中明确标注 |
