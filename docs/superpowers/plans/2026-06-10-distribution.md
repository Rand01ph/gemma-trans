# 发布工程 Implementation Plan（M3a 直分 + M3b MAS）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 产出可公证直分的 `dist/GemmaTrans-1.0.0.zip` 与可提审 MAS 的 `.pkg` + 提审材料。

**Architecture:** 证书无关部分先行（图标、Release 配置、release.sh、MAS target、bookmark、文案）；用户证书/凭据就绪后跑 M3a 全链路与 M3b spike/归档。

**Tech Stack:** XcodeGen、codesign/notarytool/stapler、App Sandbox entitlements、security-scoped bookmarks。

**Spec:** `docs/superpowers/specs/2026-06-10-distribution-design.md`

**前置（用户侧，可并行）**：Developer ID Application + Apple Distribution 证书；`xcrun notarytool store-credentials gemmatrans-notary ...`；App Store Connect app 条目。

---

### Task 1: App 图标

**Files:**
- Create: `Scripts/make-icon.swift`
- Create: `App/GemmaTrans/AppIcon.icns`（脚本产物，入库）
- Modify: `App/project.yml`

- [ ] **Step 1: 写渲染脚本**

```swift
#!/usr/bin/swift
// Scripts/make-icon.swift — 渲染占位图标（圆角渐变底 + 白色"译"字），产出 .icns
import AppKit

let variants: [(px: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
let iconset = "/tmp/GemmaTransAppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (px, name) in variants {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.05
    let path = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
        xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.65, alpha: 1)
    )!.draw(in: path, angle: -90)
    let text = NSAttributedString(string: "译", attributes: [
        .font: NSFont.systemFont(ofSize: s * 0.52, weight: .semibold),
        .foregroundColor: NSColor.white,
    ])
    let ts = text.size()
    text.draw(at: NSPoint(x: (s - ts.width) / 2, y: (s - ts.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("iconset 渲染完成: \(iconset)")
```

- [ ] **Step 2: 生成 icns 并接入工程**

Run: `swift Scripts/make-icon.swift && iconutil -c icns /tmp/GemmaTransAppIcon.iconset -o App/GemmaTrans/AppIcon.icns && ls -lh App/GemmaTrans/AppIcon.icns`
Expected: AppIcon.icns 数百 KB

project.yml 的 `info.properties` 追加：

```yaml
        CFBundleIconFile: AppIcon
```

- [ ] **Step 3: 构建验证 + Commit**

Run: `cd App && xcodegen generate && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | grep BUILD`
Expected: SUCCEEDED；`open build/Build/Products/Debug/` 看 app 图标已变。

```bash
git add Scripts/make-icon.swift App/GemmaTrans/AppIcon.icns App/project.yml
git commit -m "feat: 占位 app 图标（脚本渲染，可替换）"
```

### Task 2: Release 签名配置 + release.sh

**Files:**
- Modify: `App/project.yml`
- Create: `Scripts/release.sh`

- [ ] **Step 1: project.yml 版本与分级签名**

`targets.GemmaTrans.settings` 改为分配置：

```yaml
    settings:
      base:
        ENABLE_APP_SANDBOX: NO
        DEVELOPMENT_TEAM: G2XC9VU88M
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "6.0"
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
      configs:
        Release:
          CODE_SIGN_IDENTITY: "Developer ID Application"
          CODE_SIGN_STYLE: Manual
          ENABLE_HARDENED_RUNTIME: YES
```

- [ ] **Step 2: 写 release.sh**

```bash
#!/bin/zsh
# Scripts/release.sh — 构建、签名、公证、装订，产出 dist/GemmaTrans-<版本>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="gemmatrans-notary"
APP_DIR="App"
VERSION=$(grep 'MARKETING_VERSION' $APP_DIR/project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')

# 前置检查
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "❌ 缺少 Developer ID Application 证书。"
    echo "   Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "❌ 公证凭据未配置。先执行："
    echo "   xcrun notarytool store-credentials $PROFILE --key <p8> --key-id <KeyID> --issuer <IssuerID>"
    exit 1
fi

echo "==> 构建 Release $VERSION"
cd $APP_DIR
xcodegen generate >/dev/null
xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Release \
    -derivedDataPath build-release build | tail -2
APP="build-release/Build/Products/Release/GemmaTrans.app"

echo "==> 校验签名"
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3

echo "==> 打包并提交公证（可能数分钟）"
mkdir -p ../dist
ZIP="../dist/GemmaTrans-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> 装订并重新打包"
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 验收"
spctl --assess --type execute --verbose "$APP"
echo "✅ 完成: $ZIP"
```

- [ ] **Step 3: 验证前置检查路径 + Commit**

Run: `chmod +x Scripts/release.sh && ./Scripts/release.sh`
Expected（证书未就绪时）: 输出"❌ 缺少 Developer ID Application 证书"+ 指引，退出码 1。证书就绪后由用户触发完整跑。

```bash
git add Scripts/release.sh App/project.yml
git commit -m "feat: Release 签名配置 + 公证发布脚本"
```

注意：Release 配 Manual + Developer ID 后，Debug 构建（日常开发）不受影响。

### Task 3: MAS target + 取词编译开关

**Files:**
- Create: `App/GemmaTrans-MAS.entitlements`
- Modify: `App/project.yml`
- Modify: `App/GemmaTrans/SelectionReader.swift`

- [ ] **Step 1: entitlements 文件**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.network.server</key><true/>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.files.user-selected.read-only</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: project.yml 加 MAS target**

`targets:` 下追加（与 GemmaTrans 同级）：

```yaml
  GemmaTrans-MAS:
    type: application
    platform: macOS
    sources: [GemmaTrans]
    info:
      path: GemmaTrans/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: GemmaTrans
        CFBundleIconFile: AppIcon
    entitlements:
      path: GemmaTrans-MAS.entitlements
    dependencies:
      - package: GemmaTransCore
        product: GemmaTransKit
      - package: GemmaTransCore
        product: GemmaTransServer
      - package: KeyboardShortcuts
    settings:
      base:
        DEVELOPMENT_TEAM: G2XC9VU88M
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "6.0"
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        PRODUCT_BUNDLE_IDENTIFIER: com.gemmatrans.GemmaTrans
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) MAS_BUILD"
```

- [ ] **Step 3: SelectionReader 的 ⌘C 兜底加编译开关**

`read()` 改为：

```swift
    static func read() async -> String? {
        if let s = axSelectedText(), !s.isEmpty { return s }
        #if MAS_BUILD
        // sandbox 阻止 CGEvent 注入键盘事件；MAS 版取词 AX-only（spike 验证）
        return nil
        #else
        return await copySelectedText()
        #endif
    }
```

- [ ] **Step 4: 双 target 构建验证 + Commit**

Run: `cd App && xcodegen generate && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans-MAS -configuration Debug -derivedDataPath build build 2>&1 | grep BUILD && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | grep BUILD`
Expected: 两个 SUCCEEDED

```bash
git add App/
git commit -m "feat: MAS target（sandbox entitlements + AX-only 取词开关）"
```

### Task 4: Security-scoped bookmark（自选模型路径持久化）

**Files:**
- Modify: `Sources/GemmaTransKit/AppSettings.swift`
- Modify: `App/GemmaTrans/SettingsView.swift`
- Modify: `App/GemmaTrans/EngineController.swift`

- [ ] **Step 1: AppSettings 加 modelBookmark**

属性：`public var modelBookmark: Data?`；init 参数 `modelBookmark: Data? = nil` 并赋值；load() 追加 `s.modelBookmark = d.data(forKey: "modelBookmark")`；save() 追加 `d.set(modelBookmark, forKey: "modelBookmark")`。

- [ ] **Step 2: SettingsView 选择文件时存 bookmark**

NSOpenPanel 成功分支改为：

```swift
if panel.runModal() == .OK, let url = panel.url {
    settings.modelPath = url.path
    settings.modelBookmark = try? url.bookmarkData(
        options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
}
```

（非 sandbox 构建下 `.withSecurityScope` 同样可用，行为统一。）

- [ ] **Step 3: EngineController.start() 引擎创建前 resolve bookmark**

`let engine = TranslationEngine(settings: settings)` 之前插入：

```swift
            if let bookmark = settings.modelBookmark {
                var stale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmark, options: .withSecurityScope,
                    relativeTo: nil, bookmarkDataIsStale: &stale) {
                    _ = url.startAccessingSecurityScopedResource()  // app 生命周期内持有，不主动 stop
                    settings.modelPath = url.path
                    if stale {
                        settings.modelBookmark = try? url.bookmarkData(
                            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                        settings.save()
                    }
                }
            }
```

（`settings` 需可变：`private(set) var settings` 已是 var，方法内可改。）

- [ ] **Step 4: 全量回归 + Commit**

Run: `swift test 2>&1 | grep "Test run"; cd App && xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Debug -derivedDataPath build build 2>&1 | grep BUILD`
Expected: 测试全过 + SUCCEEDED

```bash
git add Sources/ App/
git commit -m "feat: 模型路径 security-scoped bookmark（sandbox 重启后保持可访问）"
```

### Task 5: MAS sandbox spike（需用户协助 GUI 验证）

**Files:** 无新文件（验证性任务，结论回写本计划与 spec）

- [ ] **Step 1: 运行 MAS 构建**

Run: `pkill -x GemmaTrans; open App/build/Build/Products/Debug/GemmaTrans-MAS.app`
（注意 bundle id 相同，TCC 授权沿用；模型路径在 sandbox 下解析为容器路径 `~/Library/Containers/com.gemmatrans.GemmaTrans/Data/Library/Application Support/GemmaTrans/models/`——首次需把模型文件复制/链接进去或用设置页选择原路径（走 bookmark））

- [ ] **Step 2: 验证清单（执行者跑通能自动化的，GUI 项请求用户）**

1. 引擎加载（容器内日志 `engine ready`）；GPU 推理 `/translate` 一次成功
2. API 服务可达（`network.server` 生效）
3. 用户 GUI：备忘录选中文字按 ⌥D → AX 取词路径出译文
4. 用户 GUI：VS Code（Electron）选词按 ⌥D → 预期提示"未检测到选中文本"（⌘C 兜底已禁用，确认降级符合预期）

- [ ] **Step 3: 结论回写**

把实测结论（尤其 3/4）追加到 spec 的 Spike 小节；如 AX 在 sandbox 下也不可用 → **停止 M3b 并上报**（架构性障碍，需讨论）。

```bash
git add docs/
git commit -m "docs: MAS sandbox spike 结论"
```

### Task 6: 提审材料起草

**Files:**
- Create: `docs/store-listing.md`

- [ ] **Step 1: 起草并提交**

内容四节，全部成文可直接粘贴：①商店描述（中文 + 英文，强调完全本地推理/离线/隐私）；②审核备注（说明辅助功能权限仅用于读取用户主动选中的文本送本地模型翻译，无任何网络上传；引导审核员先在设置下载模型或附测试说明）；③隐私政策全文（不收集、不传输、无第三方 SDK 数据共享；模型从 Hugging Face 下载属用户主动行为）；④提审 checklist（截图 1280×800 ×3、分类=效率、年龄分级、出口合规=使用标准加密豁免）。

```bash
git add docs/store-listing.md
git commit -m "docs: App Store 提审材料（描述/审核备注/隐私政策）"
```

### Task 7: M3a 全链路（等用户证书/凭据就绪）

- [ ] **Step 1**: 用户确认证书 + notary profile 就绪后执行 `./Scripts/release.sh`
Expected: 公证 Accepted、staple 成功、`spctl --assess` 通过、产出 `dist/GemmaTrans-1.0.0.zip`
- [ ] **Step 2**: 模拟用户下载验证：`xattr -w com.apple.quarantine "0083;00000000;Safari;" /tmp/解压后的GemmaTrans.app` 后 `open` 能直接启动无拦截
- [ ] **Step 3**: Commit（如脚本有修正）+ 把 zip 路径告知用户

### Task 8: M3b 归档与上传（等 Apple Distribution 证书 + ASC 条目）

- [ ] **Step 1**: `xcodebuild archive -project App/GemmaTrans.xcodeproj -scheme GemmaTrans-MAS -archivePath /tmp/GemmaTrans.xcarchive`
- [ ] **Step 2**: 写 `/tmp/export-options.plist`（`method: app-store`, `teamID: G2XC9VU88M`）后 `xcodebuild -exportArchive -archivePath /tmp/GemmaTrans.xcarchive -exportOptionsPlist /tmp/export-options.plist -exportPath dist/mas/`
Expected: `dist/mas/GemmaTrans.pkg`
- [ ] **Step 3**: 用户用 Transporter.app 上传 pkg → App Store Connect 填材料（用 docs/store-listing.md）→ 提审

---

## 自查

spec 覆盖：图标 ✓（T1）、Release+Hardened Runtime+版本号 ✓（T2）、release.sh 前置检查/公证/装订/验收 ✓（T2/T7）、MAS target+entitlements 四项 ✓（T3）、MAS_BUILD 取词开关 ✓（T3）、bookmark ✓（T4）、spike 双路径验证+中止条件 ✓（T5）、文案三件套 ✓（T6）、pkg 导出与上传 ✓（T8）。占位扫描：T6 列明四节具体内容要求（执行时成文）；无 TBD。类型一致：profile 名 `gemmatrans-notary`、team `G2XC9VU88M`、bundle id 全文统一。
