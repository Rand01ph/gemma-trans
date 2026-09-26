# 主线发布源码迁移

## 保留与调整

迁移前 main 的 `8138d19` 已保存为 develop，开发 PR #17 指向 develop。通过正常 PR 将产品代码恢复为已验证的 2.1.1 修复来源 `c8b8560`，保留 MIT LICENSE、仓库策略及 Cloud 验证脚本。此次不强推、不移动 tag。

App（除 ci_scripts）、Sources、Runtime、Tests 和 Package 文件与该 2.1.1 来源保持一致。旧开发源码中的扩展和 Hy-MT2 专项测试留在 develop；发布线保留对应 2.1.1 测试集合。下一版需从 develop 显式恢复被撤回的产品改动，不能只 merge 并假设 Git 自动恢复。

## 未完成门槛

本 PR 是源码准备，不能视为发布许可。Cloud 验证已首次通过，main/develop 已要求 Cloud 检查，旧 Actions 已停用；本 PR 最新源码的 Cloud 验证、main 正式归档保护、正式新 build 和图形验收仍需完成。本 PR 仅允许 main 的手动 GemmaTrans Release 归档；发布工作流默认禁用，验收前不触发。

74 张原始截图已补齐，与完整修复工作树逐张 SHA-256 一致。此为原始基线交付；最新固定图形环境验收仍未完成，不能以图片补齐或 Cloud 编译代替。

此前临时 Cloud run 39 对应 Apple build 39，已处理为 VALID；工程预设 build 40 未决定最终 Apple build，正式记录以实际产物为准，该临时包不替代 main 构建。
