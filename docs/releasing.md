# GemmaTrans macOS 发布指南

GemmaTrans 提供两条独立分发链：Developer ID 签名、公证后的 GitHub Release，以及由 Xcode Cloud 归档并上传的 Mac App Store 包。两条链都不依赖个人电脑常驻在线，也不要求安装第三方 `asc` CLI。

## 版本规则

- `MARKETING_VERSION`、`CFBundleShortVersionString` 与 Git tag 必须一致，例如 `2.0.0` / `v2.0.0`。
- `CURRENT_PROJECT_VERSION` 与 `CFBundleVersion` 必须一致。
- MAS 上传前先在 App Store Connect 确认最大 build 号，并输入更大的正整数。
- 不要在签名验收前创建 `v*` 标签；tag 会直接创建公开 GitHub Release。

## 发布凭证

Developer ID 直分发需要在 Repository Settings › Secrets and variables › Actions 配置以下 secrets。证书以带密码的 `.p12` 导出，再进行 base64 编码；私钥同样以 base64 保存。

### GitHub Release / Developer ID

- `ASC_API_KEY_P8_BASE64`
- `ASC_API_KEY_ID`
- `ASC_API_ISSUER_ID`
- `DEV_ID_CERT_P12_BASE64`
- `DEV_ID_CERT_PASSWORD`

### Mac App Store / Xcode Cloud

- Xcode Cloud 使用 App Store Connect 中的团队、签名和描述文件，不读取 GitHub Actions Secrets。
- `App/ci_scripts/ci_post_clone.sh` 负责生成 Xcode 工程并解析依赖。
- `App/ci_scripts/ci_pre_xcodebuild.sh` 保证 Cloud 使用仓库中的 `CURRENT_PROJECT_VERSION`。

GitHub Secrets 只会写入 Actions 的临时钥匙串或 `$RUNNER_TEMP`，不会进入构建产物或仓库。

## 1. 发布前 CI

PR 的 `CI` workflow 必须通过：

- Swift package tests；
- `GemmaTrans` 无签名构建；
- `GemmaTrans-MAS` 无签名构建；
- GitHub Runner 必须找到包含 macOS 26 SDK 的正式版 Xcode。

## 2. Developer ID 验收与发布

1. 在 Actions 手动运行 `Release macOS`。
2. 工作流会生成 Developer ID 签名、Apple 公证并完成 staple 的 ZIP/DMG，但不会创建公开 Release。
3. 下载 Actions artifact，验证安装、首次启动、模型管理、快捷键、浮窗和本地 API。
4. 验收通过并合并到 `main` 后，创建 `v2.0.0` tag。
5. 相同 workflow 会再次构建并把 ZIP/DMG 附加到 GitHub Release。

## 3. Mac App Store

1. 在 App Store Connect 创建或确认 `2.0.0` 版本，并查看当前最大 build 号。
2. 将 `App/project.yml` 与 `App/GemmaTrans/Info.plist` 中的 build 号同步提高并提交到目标分支。
3. 在 App Store Connect › Xcode Cloud › 构建版本中启动“发布流水线”，正式发布始终选择 `main`。
4. 工作流以 `GemmaTrans-MAS` scheme 执行 macOS Archive，并采用 App Store 分发准备。成功后等待 Apple 处理并在 TestFlight 中确认新 build。
5. 在 TestFlight 验证后，把该 build 关联到 2.0.0，更新截图、描述、What's New 和审核备注，再提交审核。

`Scripts/release-mas.sh` 与 GitHub `Release MAS (App Store)` 仅保留为故障时的备用上传路径；当前正式路径是 Xcode Cloud。

## 停止条件

出现以下任一情况时不得合并或打正式 tag：

- PR CI 未通过；
- Developer ID artifact 未通过 `codesign`、notary、staple 或 Gatekeeper；
- MAS archive 未使用 Apple Distribution 签名；
- App Store Connect build number 冲突；
- TestFlight 安装或首次模型下载流程未验收。
