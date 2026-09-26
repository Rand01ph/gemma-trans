# 本地测试通道

正式发布工程 `App/project.yml`、正式 Bundle ID 与正式设置域不变。日常运行脚本只生成独立本地工程，不再启动同标识的正式版副本。

| 通道 | Bundle ID | 默认 API 端口 | 设置域 | 默认快捷键 |
| --- | --- | --- | --- | --- |
| 正式版 | com.gemmatrans.GemmaTrans | 8765 | com.gemmatrans.app | 服务 ⌥⌘T；剪贴板 ⌥D |
| QA | com.gemmatrans.GemmaTrans.qa | 18765 | com.gemmatrans.app.qa | 服务 ⌃⌥⌘T；剪贴板 ⌃⌥D |
| Dev | com.gemmatrans.GemmaTrans.dev | 28765 | com.gemmatrans.app.dev | 默认不注册快捷键 |
| 自动测试 | com.gemmatrans.GemmaTrans.uitest | 38765 | 临时测试域 | 默认不注册快捷键 |

QA/Dev 的 API 默认关闭。系统服务分别叫 `Translate with GemmaTrans QA`、`Translate with GemmaTrans Dev`；服务快捷键可在系统设置的键盘快捷键中启用或修改。

## 使用

```sh
./script/build_and_run.sh                   # 默认通道由 script/default-channel 指定
./script/build_and_run.sh --channel qa      # 构建、安装并验证 QA
./script/build_and_run.sh --channel dev     # 构建、安装并验证 Dev
./script/build_and_run.sh --build-only      # 只构建，不安装、不启动
./script/build_and_run.sh --ui-test         # 独立 UITest 身份；结束后注销测试构建
```

2.1.1 分支默认 QA，2.2 分支默认 Dev。两条开发线共用固定通道身份，不为每个提交或 worktree 创建新应用标识。

安装入口固定为 `~/Applications/GemmaTrans QA.app`、`~/Applications/GemmaTrans Dev.app`。图标有 QA/DEV 标记，主窗口标题区分通道。菜单“关于”显示版本、分支、提交号及未提交修改标记。脚本核对 Bundle ID、签名团队、服务名称和实际进程路径，写入 `~/Library/Application Support/GemmaTrans Local Builds/<channel>/last-launch.json`。

安装只终止同通道进程，只替换 Bundle ID 匹配的目标。替换前验证签名，并将前一个版本保存在同目录管理区的 `previous.zip`。安装成功后，构建目录副本注销系统注册并移除（已验证的完整副本在固定安装位置），避免 Spotlight 再次发现同标识副本。仅 `--build-only` 会保留构建产物。无签名构建只能使用 `--build-only`；日常安装使用 Apple Development 签名。

## 数据隔离

模型位于 `~/Library/Application Support/GemmaTrans QA/models` 或 `GemmaTrans Dev/models`；日志位于 `~/Library/Logs/GemmaTrans QA` 或 `GemmaTrans Dev`。开发通道不回退到正式版的旧 Hugging Face 模型缓存。已有模型可以用 APFS clone 复制，文件目录独立，删除 QA 模型不会删除正式版文件；不要使用指向正式版模型目录的符号链接。

自动测试使用 `.uitest` 身份和 `com.gemmatrans.ui-test.*` 临时设置域。真实服务测试需在 `GemmaTrans UITest/models` 放置独立模型副本，并设置 `TEST_RUNNER_GT_SERVICE_TEST=1`。UI 自动化仍需要系统允许；签名成功不等同于自动化权限已获得。

## 历史构建治理

`python3 script/retire_local_builds.py` 只盘点本仓库所有 worktree 的散落正式标识 App；加 `--apply` 后，先生成 ZIP 并校验，再注销和移除散落 App。不会触碰 `/Applications` 的商店版、运行中的 App、`.xcarchive` 或 `.pkg`。归档清单写入 `GemmaTrans Local Builds/retired-*.json`，可按清单恢复。保留发布归档容器供签名与发布追溯。

正式身份的服务／沙盒／分发签名验收应在专门的测试账户或测试机进行。不要在日常开发账户同时注册多个正式 Bundle ID 构建；不要用清空全系统 LaunchServices 数据库代替通道隔离。
