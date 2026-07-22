#!/bin/sh
# Xcode Cloud 在 xcodebuild 之前执行：让静态 Info.plist 与 project.yml 中显式维护的
# CURRENT_PROJECT_VERSION 保持一致。测试版构建号由仓库单调递增，避免 Cloud 内部计数
# 覆盖成另一个数字，导致提交记录、TestFlight 与发布说明无法对应。
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH/App"
BUILD=$(grep 'CURRENT_PROJECT_VERSION' project.yml | head -1 | sed 's/.*"\([0-9][0-9]*\)".*/\1/')
if ! echo "$BUILD" | grep -Eq '^[1-9][0-9]*$'; then
  echo "❌ project.yml 中的 CURRENT_PROJECT_VERSION 不是正整数：$BUILD" >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" GemmaTrans/Info.plist
echo "✅ CFBundleVersion=$BUILD"
