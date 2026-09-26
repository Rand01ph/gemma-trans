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

## 当前状态（2026-09-26）

| 项目 | 状态与证据 |
| --- | --- |
| 通用策略与 AGENTS | PR #20 已合并 main，PR #22 已同步 develop |
| 发布源码 | PR #21 合并后 main 为 f27d628，产品版本 2.1.1；保留 MIT 许可和 74 张原始 UI 图片 |
| 开发集成 | develop 为 e68a81c，保留后续开发；合并后的 Cloud 集成检查 SUCCESS |
| 分支保护 | main/develop 必须经 PR 和两项 Cloud 检查；禁止强推、删除，无绕过名单。已观察到未通过时 BLOCKED、通过后 CLEAN |
| 构建归属 | Swift、checksum、已有 UI 契约、模型专项测试及应用编译由 Cloud 执行；旧 Actions 构建/发布定义已删除 |
| 旧 Cloud 入口 | Default、发布流水线、临时 2.1.1 Release 已停用 |
| 正式发布流程 | 已启用，只允许手动 main，无自动分支或 tag 触发；本次用户明确授权带已记录 UI 验收例外继续提审 |
| 最新图形验收 | 未通过；详见 [UI 验收记录](../releases/2.1.1-ui-acceptance-20260926.md) |
| 正式归档到上架 | main 8879add 正式归档成功，build 49 已提交审核，状态 WAITING_FOR_REVIEW；未上架、未打正式 tag |

## 流水线配置

- 验证：GemmaTrans Validation，ID `c0429264-37cc-4296-9907-7737d1e2f6db`。PR 到 main/develop 和 develop 更新触发。模板见 [xcode-cloud-validation.json](xcode-cloud-validation.json)。
- 正式发布：GemmaTrans Release，ID `afb3773b-8273-4e82-b80c-c4082dcc1264`。模板见 [xcode-cloud-release.json](xcode-cloud-release.json)，模板默认禁用；后台已按本次用户授权启用。
- 必需检查：`GemmaTrans | GemmaTrans Validation` 和 `GemmaTrans | GemmaTrans Validation | Build - macOS`。规则 ID `23774797`；要求解决审阅线程，当前未要求第二位评审者批准。
- `script/ci_validate.sh` 执行 checksum、Swift tests、已有 UI 契约、存在的模型专项测试及 Developer ID scheme 编译；Cloud 原生动作负责 MAS scheme。缺少 UI 契约的旧开发快照不计为 UI 验收。
- 正式包编号采用该次 `CI_BUILD_NUMBER`，静态 Info.plist 与其同步；工程本地预设值不能替代 Apple 实际产物编号。
- 首轮迁移日志确认 Swift 142 项测试、5 项 XCTest、2 项模型专项测试及 Developer ID 编译通过。发布源码 fbf0077 的 Cloud run `553a1ff3-7662-4113-a891-a50463d6409a` 成功。
- 临时预验收包实际为 build 39，不能替代 main 正式产物。正式构建前重新查询最新 build，并记录确切源 SHA。
- 监控优先使用 GitHub 回传；Apple 后台操作集中执行，避免每次进度查询都调用 1Password。

## 后续门槛

1. 最新固定图形环境验收仍有未通过项；本次用户授权例外详见 [验收记录](../releases/2.1.1-ui-acceptance-20260926.md)。后续须修复，不自动更新基线或跳过失败项。
2. main 8879add 的 build 49 已提交审核；[操作记录](../releases/2.1.1-submission-20260926.md)分别记录构建和提审结果。
3. 分别核实上传、处理、安装验收、审核与上线，按通用策略创建不可变 tag。
4. 后续版本发布时显式恢复 develop 中此次从 main 撤回的产品改动，不能假设 merge 自动恢复。现有修复/维护分支是过渡分支，不能成为永久发布主线。

## 复用到其他项目

复制 `workflow-policy.md`，新增项目自己的配置文件，再从根目录 `AGENTS.md` 引用两者。通用规则与项目 ID、测试命令、分发目标分离；通过 PR 升级策略版本，不通过本机绝对路径依赖其他仓库的文档。
