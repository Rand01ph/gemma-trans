#!/bin/zsh
# 构建、签名、公证、装订，产出 dist/GemmaTrans-<版本>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP_DIR="App"
VERSION=$(grep 'MARKETING_VERSION' $APP_DIR/project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')
# 免钥匙串：直接用 API 密钥文件（notarytool 的 keychain profile 在部分环境下读不回）
NOTARY_KEY="$HOME/.appstoreconnect/private/AuthKey_V288NX3YTW.p8"
NOTARY_KEY_ID="V288NX3YTW"
NOTARY_ISSUER="69a6de88-60c6-47e3-e053-5b8c7c11a4d1"

# 前置检查
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "❌ 缺少 Developer ID Application 证书。"
    echo "   Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
    exit 1
fi
if [ ! -f "$NOTARY_KEY" ]; then
    echo "❌ 公证密钥不存在：$NOTARY_KEY"
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
xcrun notarytool submit "$ZIP" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait

echo "==> 装订并重新打包"
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 验收"
spctl --assess --type execute --verbose "$APP"
echo "✅ 完成: $ZIP"
