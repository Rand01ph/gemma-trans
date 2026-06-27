#!/bin/zsh
# 构建 Mac App Store 版（GemmaTrans-MAS：沙盒 + Apple Distribution 签名）→ 导出 .pkg →
# 可选上传到 App Store Connect（用 asc CLI）。
# 用法：
#   Scripts/release-mas.sh            # 只构建 + 导出 .pkg
#   Scripts/release-mas.sh --upload   # 再上传到 App Store Connect
# 提审仍走 asc release stage / asc review submit（或 ASC 后台），不在此脚本内自动提交。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID="6778876828"
VERSION=$(grep 'MARKETING_VERSION' App/project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')
BUILD=$(grep 'CURRENT_PROJECT_VERSION' App/project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')
ARCH=".asc/artifacts/GemmaTrans-MAS.xcarchive"
OUT=".asc/artifacts/mas-export"

echo "==> 生成工程"
( cd App && xcodegen generate >/dev/null )

echo "==> Archive MAS $VERSION ($BUILD)"
asc xcode archive \
  --project "App/GemmaTrans.xcodeproj" \
  --scheme "GemmaTrans-MAS" \
  --configuration Release \
  --clean \
  --archive-path "$ARCH" \
  --xcodebuild-flag=-skipMacroValidation \
  --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=macOS

echo "==> 导出 .pkg（App Store Connect 方式）"
rm -rf "$OUT"
xcodebuild -exportArchive -archivePath "$ARCH" -exportPath "$OUT" \
  -exportOptionsPlist "dist/mas/ExportOptions.plist" -allowProvisioningUpdates
PKG=$(ls "$OUT"/*.pkg | head -1)
echo "✅ 导出: $PKG"

if [ "${1:-}" = "--upload" ]; then
  echo "==> 上传到 App Store Connect（app $APP_ID, $VERSION/$BUILD）"
  asc builds upload --app "$APP_ID" --pkg "$PKG" --version "$VERSION" --build-number "$BUILD" --wait
  echo "✅ 已上传。下一步：asc release stage + asc review submit（或 ASC 后台关联 $VERSION 提审）。"
fi
