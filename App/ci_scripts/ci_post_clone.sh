#!/bin/sh
# Xcode Cloud 克隆仓库后自动执行：本工程用 xcodegen 生成 .xcodeproj（不入库），
# 所以构建前必须先生成工程，否则 Xcode Cloud 找不到可构建的 project/scheme。
set -e

# Xcode Cloud runner 自带 Homebrew
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

cd "$CI_PRIMARY_REPOSITORY_PATH/App"
xcodegen generate
echo "✅ xcodegen 已生成 GemmaTrans.xcodeproj"
