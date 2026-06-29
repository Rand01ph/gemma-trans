#!/bin/sh
# Xcode Cloud 在 xcodebuild 之前执行：显式设置 build 号。
# Xcode Cloud 默认用内部构建计数当 CFBundleVersion，会低于本地已上传的 build 7 → 交付被拒
# (ITMS: bundle version must be higher than previously uploaded)。这里设成 100+CI 计数，
# 既 >7 又随每次 CI 单调递增。两个 target 共用同一个 Info.plist。
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH/App"
NEW=$((100 + ${CI_BUILD_NUMBER:-0}))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW" GemmaTrans/Info.plist
echo "✅ CFBundleVersion=$NEW"
