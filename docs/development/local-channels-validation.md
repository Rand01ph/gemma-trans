# 本地通道隔离验证

日期：2026-09-21。环境：当前开发 Mac、macOS 27、Xcode 27、Apple Development 签名。本报告只记录本地通道管理改动，不替代发布签名或完整 UI 回归验收。

## 安装结果

| 应用 | 版本 | 已安装代码提交 | 结果 |
| --- | --- | --- | --- |
| GemmaTrans QA | 2.1.1 (26) | `219c5f9f0e42` | 固定安装到 `~/Applications/GemmaTrans QA.app`，启动路径、Bundle ID、服务名称与签名校验通过 |
| GemmaTrans Dev | 2.2.0 (26) | `3d47bd907327` | 固定安装到 `~/Applications/GemmaTrans Dev.app`，启动路径、Bundle ID、服务名称与签名校验通过 |
| 商店版 GemmaTrans | 2.1.0 (25) | 原安装 | 保留 `/Applications/GemmaTrans.app`，签名校验通过，未替换应用或写入其设置 |

两个本地安装包的构建状态均为无未提交代码修改。安装后验证 QA、Dev 的构建目录 `.app` 均已移除，固定安装副本仍然有效。两者主窗口分别显示 QA、Dev，独立模型副本加载为就绪。Dev 验证后退出，QA 留作测试入口。

## 已通过

- 2.1.1 Swift Testing：134 tests / 19 suites；2.2：138 tests / 21 suites。日志分别为 `/tmp/gemma-channel-swift-tests.log`、`/tmp/gemma-channel-dev-tests.log`。
- 两条开发线的签名构建、固定路径安装和进程核验通过；日志为 `/tmp/gemma-channels-qa-latest.log`、`/tmp/gemma-channels-dev-latest.log`。
- TextEdit 真实选中文本，通过系统“服务 → Translate with GemmaTrans QA”及 QA 快捷键 `⌃⌥⌘T` 唤起 QA 翻译卡片，译文与常驻 tok/s 可见。
- 真实 Hy-MT2 4-bit 模型翻译 12 段、3514 字符的英文测试文章。完成后的卡片可访问性文本含全部 `GT001` 至 `GT012` 标记，包含文章末尾；不是模拟模型测试。该检查验证服务路由和首尾覆盖，不证明逐句语义绝无遗漏。测试源文副本保存在 `App/build/qa-service-source.rtf`。
- QA、Dev 分别使用私有设置域、模型目录、日志目录及默认端口；API 默认关闭。模型使用独立 APFS clone，未建立指向正式模型的符号链接。
- 16 个散落的旧正式身份 App 已先 ZIP 归档并校验，再注销和移除。清单位于 `~/Library/Application Support/GemmaTrans Local Builds/retired-summary.json`；发布 `.xcarchive`、`.pkg` 与商店版保留。部分旧注册项注销返回非零，不能据此宣称系统全部历史服务条目消失；QA 的独立服务名称已实际验证。
- 当前原始项目的本机 Codex Run 动作指向 2.1.1 QA，新增 Run Dev 指向 2.2 Dev；此工作区路径路由作为本机配置保留，不提交到共享仓库。

## 未通过与边界

隔离身份的原生 UI 测试已构建，但两次均在测试执行前失败：`Timed out while enabling automation mode.`。未绕过系统自动化权限。结果包在 2.1.1 工作区的 `App/build/ui-channel-isolation.xcresult`、`App/build/ui-channel-retry.xcresult`；重试日志 `/tmp/gemma-channels-ui-retry.log`。因此本轮不能报告自动 UI 验收通过；真实服务入口的手动验证与自动化失败分开记录。

本轮没有重新完成全套截图差异验收、Developer ID/MAS 发布验收，也未发布或上传。此前 2.2 设置窗口的自动 UI 问题不在本次通道修复的已验证结果中。

操作与回滚说明见 [local-channels.md](local-channels.md)。
