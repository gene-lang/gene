#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_DIR="$ROOT/example-projects/geneclaw"
GENE_BIN="$ROOT/bin/gene"
TMP_DIR="$(mktemp -d)"
HOME_DIR="$TMP_DIR/home"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p \
  "$HOME_DIR/config/llm/openai" \
  "$HOME_DIR/config/llm/anthropic" \
  "$HOME_DIR/config/documents" \
  "$HOME_DIR/workspace/sessions"

cat > "$HOME_DIR/config/llm/provider.gene" <<'EOF'
"{ENV:GENECLAW_TEST_PROVIDER:openai}"
EOF
cat > "$HOME_DIR/config/llm/openai/model.gene" <<'EOF'
"{ENV:GENECLAW_TEST_MODEL:gpt-5-mini}"
EOF
cat > "$HOME_DIR/config/llm/anthropic/model.gene" <<'EOF'
"{ENV:GENECLAW_TEST_ANTHROPIC_MODEL:claude-sonnet-4-6}"
EOF
cat > "$HOME_DIR/config/llm/max_steps.gene" <<'EOF'
"{ENV:GENECLAW_TEST_MAX_STEPS:9}"
EOF
cat > "$HOME_DIR/config/documents/max_inline_chars.gene" <<'EOF'
"{ENV:GENECLAW_TEST_INLINE:2222}"
EOF
cat > "$HOME_DIR/workspace/system_prompt.gene" <<'EOF'
"Prompt {ENV:GENECLAW_TEST_PROVIDER:openai} / {ENV:GENECLAW_TEST_MODEL:gpt-5-mini} / {ENV:GENECLAW_TEST_PROVIDER:openai}"
EOF

run_test() {
  local test_file="$1"
  shift
  (
    cd "$APP_DIR"
    env \
      GENECLAW_HOME="$HOME_DIR" \
      GENECLAW_TEST_PROVIDER="anthropic" \
      GENECLAW_TEST_MODEL="gpt-5.1-mini" \
      GENECLAW_TEST_ANTHROPIC_MODEL="claude-sonnet-4-6" \
      GENECLAW_TEST_MAX_STEPS="9" \
      GENECLAW_TEST_INLINE="2222" \
      "$@" \
      "$GENE_BIN" run "$test_file"
  )
}

run_test tests/test_home_storage_config.gene
run_test tests/test_home_storage_write.gene
run_test tests/test_home_storage_read.gene
