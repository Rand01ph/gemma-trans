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

# 公证（带重试）：国内网络连 Apple notary 的 S3 上传偶发 deadlineExceeded，自动退避重试。
notarize() {
    local file="$1" attempt=1 max=3
    while true; do
        if xcrun notarytool submit "$file" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
                --issuer "$NOTARY_ISSUER" --wait; then
            return 0
        fi
        if [ "$attempt" -ge "$max" ]; then
            echo "❌ 公证失败（已重试 $max 次）：$file"
            return 1
        fi
        echo "⚠️ 公证上传/等待失败 ${attempt}/$max；30s 后重试：$file"
        attempt=$((attempt + 1))
        sleep 30
    done
}

echo "==> 构建 Release $VERSION"
cd $APP_DIR
xcodegen generate >/dev/null
xcodebuild -project GemmaTrans.xcodeproj -scheme GemmaTrans -configuration Release \
    -skipMacroValidation -skipPackagePluginValidation \
    -derivedDataPath build-release build | tail -2
APP="build-release/Build/Products/Release/GemmaTrans.app"

echo "==> 校验签名"
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3

echo "==> 打包并提交公证（可能数分钟）"
mkdir -p ../dist
ZIP="../dist/GemmaTrans-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"

echo "==> 装订并重新打包"
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 验收 ZIP 内的 app"
spctl --assess --type execute --verbose "$APP"

echo "==> 生成 DMG（拖拽安装）"
DMG="../dist/GemmaTrans-$VERSION.dmg"
rm -f "$DMG"
if command -v create-dmg >/dev/null 2>&1; then
    # create-dmg 偶发非零退出但产物正常，故临时关 -e，事后校验产物存在
    set +e
    create-dmg \
        --volname "GemmaTrans" \
        --window-size 600 360 \
        --icon "GemmaTrans.app" 150 185 \
        --app-drop-link 450 185 \
        "$DMG" "$APP"
    set -e
else
    echo "   （create-dmg 未安装，用 hdiutil 生成基础 DMG；brew install create-dmg 可得带背景的拖拽版）"
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "GemmaTrans" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
fi
[ -f "$DMG" ] || { echo "❌ DMG 生成失败"; exit 1; }

echo "==> 公证 + 装订 DMG（可能数分钟）"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG" || true

echo "✅ 完成: $ZIP"
echo "✅ 完成: $DMG"
