# GemmaTrans 项目流程配置

规范入口：[通用策略](workflow-policy.md)。本文只补充本项目的工具与落地状态。

## 项目配置

- 当前仓库：`Rand01ph/gemma-trans`。本策略不自动授权修改其他仓库。
- 稳定主线：`main`；开发集成：`develop`；正式 tag：`vX.Y.Z`。
- 正式 macOS Bundle ID：`com.gemmatrans.GemmaTrans`；MAS scheme：`GemmaTrans-MAS`。
- 工程由 `App/project.yml` 与 XcodeGen 生成；Cloud 初始化入口为 `App/ci_scripts/`。
- 版本号与 build 在工程配置和 Info.plist 中保持一致。上传前查询 App Store Connect；Cloud run 序号单独记录，不当作 App build。
- Xcode Cloud 使用经过验证的明确 Xcode/macOS 版本；升级工具链需验证，不依赖浮动 beta 版本。
- 保留 Swift package tests、模型专项测试、UI 契约检查与正式 scheme 验证。迁移时按实际发布源码盘点测试集合，不把测试丢掉以缩短流程。
- 高保真截图与真实模型验收遵循相应 UI 契约/验证文档；固定 Mac 的图形验收不等同于云端编译成功。
- 本地 QA/Dev/UITest 使用独立身份与安装位置。已引入通道脚本的分支使用 `script/build_and_run.sh`，不以正式 ID 安装散落开发副本。
- Apple 认证材料使用 1Password 引用。发布操作可用 ASC CLI；具体保险库 ID、私钥及机器专用路径不写入共享规则。
- 商店外分发若继续维护，其构建也必须迁入统一的 Cloud 构建体系并单独验证 Developer ID、公证和安装；不得把 MAS 包视为可直接分发包，也不得悄悄恢复 Actions 构建。

## 当前迁移状态（2026-09-21 核对）

以下是迁移清单，不表示远端设置已经完成：

- [x] 确立通用策略、项目配置和 AGENTS 入口。
- [x] 从现有 main `8138d19` 保存后续开发进度到 develop，开发 PR #17 已调整目标分支。
- [ ] 通过 PR 将 main 整理为本次可发布源码；不得强推覆盖历史。
- [ ] 建立并验证 Cloud PR 检查、develop 集成检查和 main 正式发布流程。
- [x] 将 Swift、模型及已有 UI 契约检查入口迁入 Cloud；缺少契约的旧开发快照不计为 UI 验收。
- [ ] 设置 main/develop 保护规则，确认 Cloud 必需检查能阻止失败合并。
- [x] Cloud 首轮通过并设为必需检查后，停用远端 CI，删除重复 Actions 构建定义。
- [x] 已停用旧 macOS 发布工作流并删除 `v*` 自动构建定义。
- [x] 已停用并删除旧 MAS Actions 发布入口。Cloud 历史工作流仍需核对清理。
- [ ] 从整理后的 main 重新构建并验证正式产物，再按通用策略打 tag、发布。

核对时远端 main 为 `8138d19`，已有后续版本开发改动。现有临时 `codex/2.1-maintenance`、`codex/2.1.1-fixes`、`codex/2.1.1-app-store` 是过渡分支，不能成为永久发布主线。完整修复及验收证据推送尚需核实；不能把省略截图的临时构建分支当作完整验收交付。

当前临时分支的 Cloud 构建只作为预验收。即使构建成功，按新规则仍需从 main 的确定 SHA 构建正式包，并采用可用的新 build 号。所有状态在下一次操作前重新查询。

## 复用到其他项目

复制 `workflow-policy.md`，新增该项目的配置文件，再从其根目录 `AGENTS.md` 引用两者。保持通用规则与项目 ID、测试命令、分发目标分离；通过 PR 升级策略版本，不通过本机绝对路径依赖另一仓库的文档。

迁移验证分支使用 `script/ci_validate.sh` 执行 checksum、Swift tests、已有 UI 契约、Hy-MT2 专项测试及 Developer ID scheme 编译，Cloud 原生动作负责 MAS scheme。尚未引入 UI 契约的旧开发快照不宣称通过 UI 验收。分发归档继续阻止，待 main 发布源码迁移 PR 审阅后再放行。旧 Actions 验证在替代检查通过并设为必需前保留。

## Cloud 迁移实证

- Cloud 验证工作流：`c0429264-37cc-4296-9907-7737d1e2f6db`（GemmaTrans Validation），PR 到 main/develop 自动触发，develop 更新触发集成验证。
- 首轮 PR #20：源 `785284d`，run `89cda31d-7fc8-45ed-89f5-4bc5e7777640`，GitHub Cloud 总状态及 Build 动作均 SUCCESS；不是正式归档，也不替代图形验收。
- main/develop 规则 `23774797` 已启用：PR、禁止删除/强推、解决审阅线程、最新主线及 Cloud 两项必需检查，无绕过名单。当前未要求第二位评审者批准。
- 必需检查：`GemmaTrans | GemmaTrans Validation` 与 `GemmaTrans | GemmaTrans Validation | Build - macOS`。旧 Actions 已远端停用；迁移中新提交仍须重新通过 Cloud。
- 当前工作流定义见 `xcode-cloud-validation.json`；正式 main 归档、develop 实际集成验证及固定环境 UI 验收尚未完成。
- 监控优先读取 GitHub 回传；仅在实际需要 Apple API 操作时使用凭证，并批量执行，避免每次进度查询都调用 1Password。

2026-09-22：策略 PR #20 已合并 main（120a301）。三个旧 public Cloud 入口均已停用；开发同步 PR #22 进行中。日志确认首轮 Swift 142 项测试、5 项 XCTest、2 项模型专项测试及 Developer ID 编译通过。正式流程模板见 `xcode-cloud-release.json`，默认禁用；仅允许 main 的手动 GemmaTrans Release 归档，Cloud build 号为正式包编号。启用前必须完成发布验收。

74 张原始 UI 截图已补传并逐张校验 SHA-256，纳入主线发布源码 PR #21。正式发布工作流的 JSON 模板已提交，但 Apple 后台创建因 1Password 授权超时尚未执行，不得将模板视为已部署流程。
