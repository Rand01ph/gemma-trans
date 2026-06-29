#!/bin/sh
# Xcode Cloud 克隆仓库后自动执行：
# 1) 本工程用 xcodegen 生成 .xcodeproj（不入库），构建前必须先生成；
# 2) Xcode Cloud 默认禁用自动依赖解析、只认 committed Package.resolved。但本工程的
#    .xcodeproj 是现生成的、App target 额外加了 KeyboardShortcuts，committed 的根
#    Package.resolved 覆盖不全 → 重新允许自动解析，让 Xcode 在构建时现解依赖。
set -e

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

cd "$CI_PRIMARY_REPOSITORY_PATH/App"
xcodegen generate
echo "✅ xcodegen 已生成 GemmaTrans.xcodeproj"

# 重新打开自动依赖解析（Xcode Cloud 在 post-clone 前用 defaults 关闭了它们）
defaults write com.apple.dt.Xcode IDEDisableAutomaticPackageResolution -bool NO || true
defaults write com.apple.dt.Xcode IDEPackageOnlyUseVersionsFromResolvedFile -bool NO || true

# 显式预解析一次，确保完整的 Package.resolved 就位
xcodebuild -resolvePackageDependencies \
  -project GemmaTrans.xcodeproj -scheme GemmaTrans-MAS \
  -skipMacroValidation || true
echo "✅ 依赖解析完成"
