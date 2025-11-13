#!/usr/bin/env bash
set -euo pipefail

# Download script for small LLM models compatible with llama.cpp
# Optimized for testing on Apple Silicon M series

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/../tmp/models"

mkdir -p "$MODELS_DIR"

echo "🤖 Gene LLM Model Downloader"
echo "📍 Models directory: $MODELS_DIR"
echo ""

# Model list - small models suitable for testing
declare -a MODELS=(
    # Tiny model - fastest for testing
    "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"

    # Small but capable model
    "https://huggingface.co/TheBloke/Qwen1.5-1.8B-Chat-GGUF/resolve/main/qwen1.5-1.8b-chat.Q4_K_M.gguf"

    # Popular small model
    "https://huggingface.co/TheBloke/Phi-3-mini-4k-instruct-GGUF/resolve/main/phi-3-mini-4k-instruct-q4.gguf"
)

declare -a MODEL_NAMES=(
    "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    "qwen1.5-1.8b-chat.Q4_K_M.gguf"
    "phi-3-mini-4k-instruct-q4.gguf"
)

download_model() {
    local url="$1"
    local filename="$2"
    local filepath="$MODELS_DIR/$filename"

    if [ -f "$filepath" ]; then
        echo "✅ Already downloaded: $filename"
        return 0
    fi

    echo "📥 Downloading: $filename"
    echo "   From: $(basename "$url")"
    echo "   To: $filepath"

    # Use curl with resume support and progress bar
    if curl -L --progress-bar --continue-at - -o "$filepath" "$url"; then
        local size=$(du -h "$filepath" | cut -f1)
        echo "✅ Downloaded: $filename ($size)"
    else
        echo "❌ Failed to download: $filename"
        return 1
    fi
}

echo "🔍 Available models for download:"
for i in "${!MODEL_NAMES[@]}"; do
    name="${MODEL_NAMES[$i]}"
    filepath="$MODELS_DIR/$name"
    if [ -f "$filepath" ]; then
        size=$(du -h "$filepath" | cut -f1)
        echo "   ✅ $name ($size) - [DOWNLOADED]"
    else
        echo "   ⬇️  $name - [NOT DOWNLOADED]"
    fi
done

echo ""
echo "🚀 Starting downloads..."

# Download models
success_count=0
for i in "${!MODELS[@]}"; do
    url="${MODELS[$i]}"
    name="${MODEL_NAMES[$i]}"

    if download_model "$url" "$name"; then
        ((success_count++))
    fi
    echo ""
done

echo "📊 Download Summary:"
echo "   Successful: $success_count/${#MODELS[@]}"
echo "   Models directory: $MODELS_DIR"

# List downloaded models
if [ "$(ls -A "$MODELS_DIR" 2>/dev/null)" ]; then
    echo ""
    echo "📁 Downloaded models:"
    ls -lh "$MODELS_DIR"/*.gguf 2>/dev/null | while read -r line; do
        echo "   $line"
    done
else
    echo ""
    echo "⚠️  No models downloaded. Check your internet connection."
fi

echo ""
echo "💡 Usage example in Gene:"
echo "   (load_model \"models/$(ls "$MODELS_DIR"/*.gguf 2>/dev/null | head -1 | xargs basename -a)\")"