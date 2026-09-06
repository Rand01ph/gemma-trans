#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${GT_LLAMA_BUILD_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/gemmatrans-llama-runtime.XXXXXX")}" 
OUTPUT_DIR="${GT_LLAMA_OUTPUT_DIR:-$SCRIPT_DIR/Artifacts}"
SOURCE_DIR="$WORK_DIR/llama.cpp"
BUILD_DIR="$WORK_DIR/build"
PRODUCT_DIR="$WORK_DIR/product"
BASELINE_COMMIT="1e411d8f5a1e23525fa3265dfb4bd76265465397"

cleanup() {
    if [[ -z "${GT_LLAMA_BUILD_DIR:-}" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$PRODUCT_DIR/Headers"
git init -q "$SOURCE_DIR"
git -C "$SOURCE_DIR" remote add origin https://github.com/ggml-org/llama.cpp.git
git -C "$SOURCE_DIR" fetch -q --depth 1 origin "$BASELINE_COMMIT"
git -C "$SOURCE_DIR" checkout -q --detach FETCH_HEAD
git -C "$SOURCE_DIR" apply --check "$SCRIPT_DIR/patches/combined.patch"
git -C "$SOURCE_DIR" apply "$SCRIPT_DIR/patches/combined.patch"

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=OFF \
    -DGGML_CPU_KLEIDIAI=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_COMMON=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_APP=OFF \
    -DLLAMA_BUILD_MTMD=OFF \
    -DGGML_BUILD_TESTS=OFF

cmake --build "$BUILD_DIR" --target llama llama-common -j "$(sysctl -n hw.ncpu)"

xcrun clang++ -std=c++17 -O3 -DNDEBUG -arch arm64 -mmacosx-version-min=15.0 \
    -I"$SCRIPT_DIR/Sources/include" \
    -I"$SOURCE_DIR/include" \
    -I"$SOURCE_DIR/ggml/include" \
    -I"$SOURCE_DIR/common" \
    -I"$SOURCE_DIR/vendor" \
    -I"$SOURCE_DIR/vendor/nlohmann" \
    -c "$SCRIPT_DIR/Sources/GemmaLlamaRuntime.cpp" \
    -o "$PRODUCT_DIR/GemmaLlamaRuntime.o"

# llama-common also contains optional download/HTTP/subprocess helpers. The runtime needs only the
# chat-template/Jinja closure below; extract that audited object set so the XCFramework cannot expose
# llama.cpp network, server, tool or subprocess entry points.
COMMON_OBJECT_DIR="$PRODUCT_DIR/CommonObjects"
mkdir -p "$COMMON_OBJECT_DIR"
(
    cd "$COMMON_OBJECT_DIR"
    ar -x "$BUILD_DIR/common/libllama-common.a"
    ar -x "$BUILD_DIR/common/libllama-common-base.a"
)
COMMON_OBJECT_NAMES=(
    build-info.cpp.o
    caps.cpp.o
    chat-auto-parser-generator.cpp.o
    chat-auto-parser-helpers.cpp.o
    chat-diff-analyzer.cpp.o
    chat-peg-parser.cpp.o
    chat.cpp.o
    common.cpp.o
    fit.cpp.o
    json-schema-to-grammar.cpp.o
    lexer.cpp.o
    log.cpp.o
    parser.cpp.o
    peg-parser.cpp.o
    reasoning-budget.cpp.o
    runtime.cpp.o
    sampling.cpp.o
    string.cpp.o
    trie.cpp.o
    unicode.cpp.o
    value.cpp.o
)
COMMON_OBJECTS=()
for object_name in "${COMMON_OBJECT_NAMES[@]}"; do
    object_path="$COMMON_OBJECT_DIR/$object_name"
    if [[ ! -f "$object_path" ]]; then
        echo "missing audited llama-common object: $object_name" >&2
        exit 1
    fi
    COMMON_OBJECTS+=("$object_path")
done

ZERO_AR_DATE=1 /usr/bin/libtool -static -o "$PRODUCT_DIR/libLlamaRuntime.a" \
    "$PRODUCT_DIR/GemmaLlamaRuntime.o" \
    "${COMMON_OBJECTS[@]}" \
    "$BUILD_DIR/src/libllama.a" \
    "$BUILD_DIR/ggml/src/libggml.a" \
    "$BUILD_DIR/ggml/src/libggml-cpu.a" \
    "$BUILD_DIR/ggml/src/ggml-blas/libggml-blas.a" \
    "$BUILD_DIR/ggml/src/libggml-base.a" \
    "$BUILD_DIR/_deps/kleidiai-build/libkleidiai.a"

if nm -gU "$PRODUCT_DIR/libLlamaRuntime.a" | \
    grep -Eq 'common_download|common_http_url|httplib|curl_easy|curl_multi'; then
    echo "runtime archive unexpectedly contains network/download symbols" >&2
    exit 1
fi

MIN_OS_VALUES="$(xcrun otool -l "$PRODUCT_DIR/libLlamaRuntime.a" | \
    awk '$1 == "minos" { print $2 }' | LC_ALL=C sort -u)"
if [[ -z "$MIN_OS_VALUES" ]]; then
    echo "runtime archive does not contain LC_BUILD_VERSION minos metadata" >&2
    exit 1
fi
if ! printf '%s\n' "$MIN_OS_VALUES" | awk -F. '
    { major = $1 + 0; minor = $2 + 0 }
    major > 15 || (major == 15 && minor > 0) { exit 1 }
'; then
    echo "runtime archive contains an object newer than macOS 15.0: $MIN_OS_VALUES" >&2
    exit 1
fi
echo "Runtime minimum macOS versions: $MIN_OS_VALUES"

cp "$SCRIPT_DIR/Sources/include/GemmaLlamaRuntime.h" "$PRODUCT_DIR/Headers/"
cp "$SCRIPT_DIR/Sources/include/module.modulemap" "$PRODUCT_DIR/Headers/"

rm -rf "$OUTPUT_DIR/LlamaRuntime.xcframework"
xcodebuild -create-xcframework \
    -library "$PRODUCT_DIR/libLlamaRuntime.a" \
    -headers "$PRODUCT_DIR/Headers" \
    -output "$OUTPUT_DIR/LlamaRuntime.xcframework"

find "$OUTPUT_DIR/LlamaRuntime.xcframework" -exec touch -h -t 202001010000 {} +
rm -f "$OUTPUT_DIR/LlamaRuntime-2.2.0-r1.zip"
(
    cd "$OUTPUT_DIR"
    find LlamaRuntime.xcframework -print | LC_ALL=C sort | \
        COPYFILE_DISABLE=1 zip -X -q "LlamaRuntime-2.2.0-r1.zip" -@
)

file "$PRODUCT_DIR/libLlamaRuntime.a"
shasum -a 256 "$OUTPUT_DIR/LlamaRuntime-2.2.0-r1.zip"
swift package compute-checksum "$OUTPUT_DIR/LlamaRuntime-2.2.0-r1.zip"
