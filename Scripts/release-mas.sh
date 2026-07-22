#!/bin/zsh
# 构建 Mac App Store 版（GemmaTrans-MAS：沙盒 + Apple Distribution 签名）→ 导出 .pkg →
# 可选上传到 App Store Connect。仅使用 Xcode 自带工具，不依赖第三方 asc CLI。
# 用法：
#   Scripts/release-mas.sh            # 只构建 + 导出 .pkg
#   Scripts/release-mas.sh --upload   # 再上传到 App Store Connect
# 上传需要 ASC_API_KEY_ID / ASC_API_ISSUER_ID，私钥放在
# ~/.appstoreconnect/private/AuthKey_<ASC_API_KEY_ID>.p8。提审仍在 ASC 后台完成。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep 'MARKETING_VERSION' App/project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')
BUILD=$(grep 'CURRENT_PROJECT_VERSION' App/project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')
ARCH="App/build-mas/GemmaTrans-MAS.xcarchive"
OUT="App/build-mas/export"

echo "==> 生成工程"
( cd App && xcodegen generate >/dev/null )

echo "==> Archive MAS $VERSION ($BUILD)"
rm -rf "$ARCH"
xcodebuild -project "App/GemmaTrans.xcodeproj" \
  -scheme "GemmaTrans-MAS" \
  -configuration Release \
  -skipMacroValidation -skipPackagePluginValidation \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCH" \
  clean archive

echo "==> 导出 .pkg（App Store Connect 方式）"
rm -rf "$OUT"
xcodebuild -exportArchive -archivePath "$ARCH" -exportPath "$OUT" \
  -exportOptionsPlist "dist/mas/ExportOptions.plist" -allowProvisioningUpdates
PKG=$(ls "$OUT"/*.pkg | head -1)
echo "✅ 导出: $PKG"

if [ "${1:-}" = "--upload" ]; then
  : "${ASC_API_KEY_ID:?请设置 ASC_API_KEY_ID}"
  : "${ASC_API_ISSUER_ID:?请设置 ASC_API_ISSUER_ID}"
  KEY="$HOME/.appstoreconnect/private/AuthKey_${ASC_API_KEY_ID}.p8"
  [ -f "$KEY" ] || { echo "❌ App Store Connect API 私钥不存在：$KEY"; exit 1; }
  echo "==> 上传到 App Store Connect（$VERSION/$BUILD）"
  xcrun altool --upload-app -t macos -f "$PKG" \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_API_ISSUER_ID"
  echo "✅ 已上传。下一步：在 App Store Connect 关联 $VERSION ($BUILD) 并提交审核。"
fi
