# GemmaTrans macOS 发布指南

GemmaTrans 提供两条独立分发链：Developer ID 签名、公证后的 GitHub Release，以及 Apple Distribution 签名的 Mac App Store 包。两条链都运行在 GitHub 托管的 macOS Runner 上，不依赖个人电脑常驻在线，也不要求安装第三方 `asc` CLI。

## 版本规则

- `MARKETING_VERSION`、`CFBundleShortVersionString` 与 Git tag 必须一致，例如 `2.0.0` / `v2.0.0`。
- `CURRENT_PROJECT_VERSION` 与 `CFBundleVersion` 必须一致。
- MAS 上传前先在 App Store Connect 确认最大 build 号，并输入更大的正整数。
- 不要在签名验收前创建 `v*` 标签；tag 会直接创建公开 GitHub Release。

## Actions Secrets

在 Repository Settings › Secrets and variables › Actions 配置以下 secrets。证书以带密码的 `.p12` 导出，再进行 base64 编码；私钥与描述文件同样以 base64 保存。

### 两条发布链共用

- `ASC_API_KEY_P8_BASE64`
- `ASC_API_KEY_ID`
- `ASC_API_ISSUER_ID`

### GitHub Release / Developer ID

- `DEV_ID_CERT_P12_BASE64`
- `DEV_ID_CERT_PASSWORD`

### Mac App Store

- `MAS_DIST_CERT_P12_BASE64`
- `MAS_DIST_CERT_PASSWORD`
- `MAS_INSTALLER_CERT_P12_BASE64`
- `MAS_INSTALLER_CERT_PASSWORD`
- `MAS_PROVISION_PROFILE_BASE64`

Secrets 只会写入 Actions 的临时钥匙串或 `$RUNNER_TEMP`，不会进入构建产物或仓库。

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
2. 在 Actions 手动运行 `Release MAS (App Store)`，输入更高的 build number。
3. 工作流使用 `GemmaTrans-MAS` archive、导出 Apple Distribution `.pkg` 并上传 App Store Connect。
4. 在 TestFlight 验证后，关联该 build、更新截图和审核备注，再提交审核。

本地也可以运行 `Scripts/release-mas.sh` 归档和导出；加入 `--upload` 时需要设置 `ASC_API_KEY_ID`、`ASC_API_ISSUER_ID` 并把私钥放到 `~/.appstoreconnect/private/AuthKey_<ID>.p8`。整个流程使用 `xcodebuild` 与 `xcrun altool`，不依赖 `asc`。

## 停止条件

出现以下任一情况时不得合并或打正式 tag：

- PR CI 未通过；
- Developer ID artifact 未通过 `codesign`、notary、staple 或 Gatekeeper；
- MAS archive 未使用 Apple Distribution 签名；
- App Store Connect build number 冲突；
- TestFlight 安装或首次模型下载流程未验收。
