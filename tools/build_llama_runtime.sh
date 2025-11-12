#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_DIR="$ROOT_DIR/tools/llama.cpp"
BUILD_DIR="$ROOT_DIR/build/llama"
SHIM_SRC="$ROOT_DIR/src/genex/llm/shim/gene_llm.cpp"

if [ ! -d "$LLAMA_DIR" ]; then
  echo "llama.cpp submodule is missing. Run 'git submodule update --init --recursive tools/llama.cpp'." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

declare -a EXTRA_CMAKE_FLAGS=()
if [ "${GENE_LLAMA_METAL:-0}" = "1" ]; then
  EXTRA_CMAKE_FLAGS+=("-DGGML_METAL=ON")
fi
if [ "${GENE_LLAMA_CUDA:-0}" = "1" ]; then
  EXTRA_CMAKE_FLAGS+=("-DGGML_CUDA=ON")
fi

cmake_args=(
  -S "$LLAMA_DIR"
  -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DLLAMA_BUILD_TESTS=OFF
  -DLLAMA_BUILD_TOOLS=OFF
  -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_BUILD_SERVER=OFF
  -DLLAMA_BUILD_STANDALONE=OFF
  -DLLAMA_ALL_WARNINGS=OFF
)
if [ ${#EXTRA_CMAKE_FLAGS[@]} -gt 0 ]; then
  cmake_args+=("${EXTRA_CMAKE_FLAGS[@]}")
fi

cmake "${cmake_args[@]}"

cmake --build "$BUILD_DIR" --target llama --config Release -j"$(sysctl -n hw.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

if [ -f "$BUILD_DIR/src/libllama.a" ]; then
  cp "$BUILD_DIR/src/libllama.a" "$BUILD_DIR/libllama.a"
fi

clang++ -std=c++17 -O3 -fPIC \
  -I"$LLAMA_DIR/include" \
  -I"$LLAMA_DIR/ggml/include" \
  -I"$LLAMA_DIR" \
  -c "$SHIM_SRC" -o "$BUILD_DIR/gene_llm.o"

ar rcs "$BUILD_DIR/libgene_llm.a" "$BUILD_DIR/gene_llm.o"

echo "llama runtime built at $BUILD_DIR"
