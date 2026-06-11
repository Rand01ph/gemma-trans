#!/bin/zsh
# 构建、签名、公证、装订，产出 dist/GemmaTrans-<版本>.zip
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
xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Release -skipMacroValidation \
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
