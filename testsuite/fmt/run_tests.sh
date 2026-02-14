#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENE="$SCRIPT_DIR/../../bin/gene"

if [ ! -f "$GENE" ]; then
  echo -e "${RED}Error: gene executable not found at $GENE${NC}"
  echo "Please run 'nimble build' first."
  exit 1
fi

PASSED=0
FAILED=0
TOTAL=0

pass() {
  printf "  %-44s ${GREEN}✓ PASS${NC}\n" "$1"
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
}

fail() {
  printf "  %-44s ${RED}✗ FAIL${NC}\n" "$1"
  if [ -n "${2:-}" ]; then
    echo "    $2"
  fi
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
}

assert_file_equal() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if diff -u "$expected" "$actual" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "Output differs from expected fixture"
  fi
}

echo -e "${BLUE}Testing gene fmt:${NC}"

# 1) Canonical fixture remains unchanged.
TMP_CANON="$(mktemp)"
cp "$SCRIPT_DIR/cases/canonical.gene" "$TMP_CANON"
"$GENE" fmt "$TMP_CANON" >/dev/null
assert_file_equal "canonical file unchanged" "$TMP_CANON" "$SCRIPT_DIR/cases/canonical.gene"
rm -f "$TMP_CANON"

# 2) Indentation and trailing whitespace normalization.
TMP_MESSY="$(mktemp)"
cp "$SCRIPT_DIR/cases/messy.input.gene" "$TMP_MESSY"
"$GENE" fmt "$TMP_MESSY" >/dev/null
assert_file_equal "fixes indentation/trailing ws" "$TMP_MESSY" "$SCRIPT_DIR/cases/messy.expected.gene"
rm -f "$TMP_MESSY"

# 3) Shebang/comments/blank lines are preserved.
TMP_SHEBANG="$(mktemp)"
cp "$SCRIPT_DIR/cases/shebang_comments.input.gene" "$TMP_SHEBANG"
"$GENE" fmt "$TMP_SHEBANG" >/dev/null
assert_file_equal "preserves shebang/comments" "$TMP_SHEBANG" "$SCRIPT_DIR/cases/shebang_comments.expected.gene"
rm -f "$TMP_SHEBANG"

# 4) --check fails on non-canonical input and does not modify file.
TMP_CHECK_FAIL="$(mktemp)"
cp "$SCRIPT_DIR/cases/messy.input.gene" "$TMP_CHECK_FAIL"
set +e
"$GENE" fmt --check "$TMP_CHECK_FAIL" >/dev/null 2>&1
CHECK_EXIT=$?
set -e
if [ "$CHECK_EXIT" -ne 0 ]; then
  pass "--check fails on non-canonical"
else
  fail "--check fails on non-canonical" "Expected non-zero exit for non-canonical file"
fi
assert_file_equal "--check leaves file unchanged" "$TMP_CHECK_FAIL" "$SCRIPT_DIR/cases/messy.input.gene"
rm -f "$TMP_CHECK_FAIL"

# 5) --check passes on canonical input.
set +e
"$GENE" fmt --check "$SCRIPT_DIR/cases/canonical.gene" >/dev/null 2>&1
CHECK_PASS_EXIT=$?
set -e
if [ "$CHECK_PASS_EXIT" -eq 0 ]; then
  pass "--check passes on canonical"
else
  fail "--check passes on canonical" "Expected zero exit for canonical file"
fi

# 6) Golden check: examples/full.gene should already be canonical.
set +e
"$GENE" fmt --check "$SCRIPT_DIR/../../examples/full.gene" >/dev/null 2>&1
GOLDEN_EXIT=$?
set -e
if [ "$GOLDEN_EXIT" -eq 0 ]; then
  pass "examples/full.gene golden check"
else
  fail "examples/full.gene golden check" "Formatter does not treat examples/full.gene as canonical"
fi

echo
printf "  Total:  %3d\n" "$TOTAL"
printf "  Passed: %3d\n" "$PASSED"
printf "  Failed: %3d\n" "$FAILED"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
