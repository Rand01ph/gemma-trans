# GemmaTrans 发布工程设计（M3a 公证直分 + M3b App Store）

日期：2026-06-10
状态：已确认

## 用户侧准备（一次性，与代码开工并行）

1. Xcode → Settings → Accounts → Manage Certificates 创建：`Developer ID Application`（M3a，需账号持有人角色）、`Apple Distribution`（M3b）。
2. App Store Connect 创建 API 密钥（App Manager），本机执行一次
   `xcrun notarytool store-credentials gemmatrans-notary --key <p8> --key-id <KeyID> --issuer <IssuerID>`
   ——发布脚本只引用 profile 名 `gemmatrans-notary`，密钥不进仓库。
3. M3b 提审前：App Store Connect 建 app 条目（bundle id `com.gemmatrans.GemmaTrans`）。

## M3a：公证直分

- **图标**：当前无图标（分发必需）。用 Swift 脚本（`Scripts/make-icon.swift`，NSImage 绘制气泡+"译"字形，渐变底）渲染 1024px 起的全尺寸 iconset → `iconutil` 产出 `App/GemmaTrans/AppIcon.icns`，XcodeGen `info.properties` 配 `CFBundleIconFile`。占位性质，可随时替换设计稿。
- **Release 签名配置**：project.yml 增加 `MARKETING_VERSION: "1.0.0"`、`CURRENT_PROJECT_VERSION: 1`；Release 配置 `CODE_SIGN_IDENTITY: "Developer ID Application"`、`ENABLE_HARDENED_RUNTIME: YES`（Debug 维持 Apple Development）。
- **`Scripts/release.sh`**：前置检查（Developer ID 证书存在、notary profile 存在，缺则输出准备指引并退出）→ `xcodebuild -configuration Release` → `codesign --verify --deep --strict` → `ditto -c -k --keepParent` 打 zip → `xcrun notarytool submit --keychain-profile gemmatrans-notary --wait` → `xcrun stapler staple` → 重新打最终 zip 到 `dist/GemmaTrans-<MARKETING_VERSION>.zip`。
- **验收**：`spctl --assess --type execute` 通过；`xattr -w com.apple.quarantine` 模拟下载来源后能直接打开。

## M3b：MAS 化

- **XcodeGen 第二 target `GemmaTrans-MAS`**：同源码、同 bundle id；差异仅 entitlements 与签名：
  - `com.apple.security.app-sandbox: true`
  - `com.apple.security.network.server: true`（本地 API）
  - `com.apple.security.network.client: true`（单实例探测/模型下载）
  - `com.apple.security.files.user-selected.read-only: true`（自选模型文件）
  - 签名 `Apple Distribution` + provisioning（Xcode 自动管理）。
- **Spike（M3b 第一任务，结果决定后续）**：构建 MAS target 本机运行，授予辅助功能后实测：① AX 读选中文本；② 模拟 ⌘C。预期 ① 可行（PopClip/Magnet 先例）、② 被 sandbox 拦截。若 ② 不可用：MAS 构建经编译开关（`MAS_BUILD` Swift flag）禁用 ⌘C 兜底，取词 AX-only，商店描述注明部分 Electron app 取词受限。
- **Spike 实测结论（2026-06-10，自动化部分）**：✅ sandbox 内引擎加载成功（容器路径模型，硬链接验证）；✅ Metal/WebGPU GPU 推理正常（真实翻译通过）；✅ `network.server` 生效（127.0.0.1:8765 可达）；✅ 自动调优在沙盒内工作（内存压力降档生效）；✅ GPU 编译缓存写入容器内 Caches。⌘C 兜底已按预期经 `MAS_BUILD` 禁用未实测（sandbox 公开规则即禁止 CGEvent 注入）。待用户 GUI 验证：AX 取词热键路径、Electron app 降级提示。
- **Security-scoped bookmark**：sandbox 下 NSOpenPanel 授权重启失效。`AppSettings` 增加 `modelBookmark: Data?`；设置页选择模型文件时保存 bookmark，引擎加载前 resolve + `startAccessingSecurityScopedResource`。默认容器内路径不受影响。
- **产出与上传**：`xcodebuild archive` + `-exportArchive`（method `app-store`）产出 `.pkg`；上传用 Transporter.app（用户拖拽）或 `xcrun altool` 可用时走 CLI。
- **文案（我起草，用户粘贴）**：商店描述（中英）、审核备注（辅助功能用途 = 读取用户主动选中的文本用于本地翻译；模型本地推理、零网络上传）、隐私政策（不收集任何数据）。

## 交付顺序

证书无关部分先行：图标 → Release 配置 + release.sh（带前置检查）→ MAS target + spike。用户证书/凭据就绪后：跑通 M3a 全链路 → M3b sandbox 适配收尾 → 产出 pkg + 提审材料。

## 风险

- MAS 审核对辅助功能权限的尺度不可保证（有 PopClip/Magnet 先例）；被拒不影响直分渠道。
- sandbox 下 LiteRT Metal/WebGPU 与缓存目录行为未验证——spike 一并覆盖（容器内 Caches 可写，预期无碍）。

## 不做（YAGNI）

DMG 包装（zip 足够）、Sparkle 自动更新、CI 流水线、多语言商店页（先中英）。
