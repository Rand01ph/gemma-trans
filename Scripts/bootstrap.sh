#!/bin/zsh
# 拉取 vendor 依赖。LiteRT-LM 必须本地路径引用（其 unsafeFlags 不被 SPM 远程版本依赖允许）。
set -euo pipefail

LITERT_TAG="v0.13.1"
VENDOR_DIR="$(dirname "$0")/../Vendor/LiteRT-LM"

if [ -d "$VENDOR_DIR/.git" ]; then
    echo "LiteRT-LM 已存在: $VENDOR_DIR ($(git -C "$VENDOR_DIR" describe --tags))"
else
    echo "浅克隆 LiteRT-LM $LITERT_TAG …"
    git clone --depth 1 --branch "$LITERT_TAG" \
        https://github.com/google-ai-edge/LiteRT-LM "$VENDOR_DIR"
fi
echo "bootstrap 完成。"
