#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_DIR="$ROOT_DIR/tools/llama.cpp"
BUILD_DIR="$ROOT_DIR/build/llama"
SHIM_SRC="$ROOT_DIR/src/genex/llm/shim/gene_llm.cpp"

# Auto-detect Apple Silicon and enable Metal support
ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
  echo "🍎 Detected Apple Silicon ($ARCH), enabling Metal acceleration"
  export GENE_LLAMA_METAL=1
  # For Apple Silicon, ensure we're using the right architecture
  CMAKE_ARCH_FLAGS="-DCMAKE_OSX_ARCHITECTURES=arm64"
else
  echo "💻 Detected Intel/Other architecture ($ARCH)"
  CMAKE_ARCH_FLAGS=""
fi

# Initialize submodule if missing
if [ ! -d "$LLAMA_DIR" ] || [ -z "$(ls -A "$LLAMA_DIR" 2>/dev/null)" ]; then
  echo "📦 Initializing llama.cpp submodule..."
  cd "$ROOT_DIR"
  git submodule update --init --recursive tools/llama.cpp
  cd "$ROOT_DIR/tools"
fi

mkdir -p "$BUILD_DIR"

declare -a EXTRA_CMAKE_FLAGS=()
if [ "${GENE_LLAMA_METAL:-0}" = "1" ]; then
  EXTRA_CMAKE_FLAGS+=("-DGGML_METAL=ON")
  echo "⚡ Metal acceleration enabled"
fi
if [ "${GENE_LLAMA_CUDA:-0}" = "1" ]; then
  EXTRA_CMAKE_FLAGS+=("-DGGML_CUDA=ON")
  echo "🚀 CUDA acceleration enabled"
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
if [ -n "$CMAKE_ARCH_FLAGS" ]; then
  cmake_args+=($CMAKE_ARCH_FLAGS)
fi

echo "🔧 Configuring llama.cpp with: ${cmake_args[*]}"
cmake "${cmake_args[@]}"

echo "🏗️  Building llama.cpp library..."
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
cmake --build "$BUILD_DIR" --target llama --config Release -j"$JOBS"

# Find the built library location
if [ -f "$BUILD_DIR/src/libllama.a" ]; then
  cp "$BUILD_DIR/src/libllama.a" "$BUILD_DIR/libllama.a"
  echo "✅ Found libllama.a in src/"
elif [ -f "$BUILD_DIR/libllama.a" ]; then
  echo "✅ Found libllama.a in build root"
else
  echo "❌ Could not find libllama.a after build"
  ls -la "$BUILD_DIR"
  find "$BUILD_DIR" -name "*.a" -type f
  exit 1
fi

echo "🔗 Building Gene LLM shim..."
clang++ -std=c++17 -O3 -fPIC \
  -I"$LLAMA_DIR/include" \
  -I"$LLAMA_DIR/ggml/include" \
  -I"$LLAMA_DIR" \
  -c "$SHIM_SRC" -o "$BUILD_DIR/gene_llm.o"

ar rcs "$BUILD_DIR/libgene_llm.a" "$BUILD_DIR/gene_llm.o"

echo "✅ Llama runtime built successfully at $BUILD_DIR"
echo "📁 Libraries: libllama.a $(ls -la "$BUILD_DIR/libllama.a" | awk '{print $5}' | numfmt --to=iec)"
echo "📁 Shim: libgene_llm.a $(ls -la "$BUILD_DIR/libgene_llm.a" | awk '{print $5}' | numfmt --to=iec)"
