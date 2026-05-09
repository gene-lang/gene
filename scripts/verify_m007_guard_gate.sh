#!/usr/bin/env bash
# Repeatable M007 runtime guard migration gate.
# Run from the repository root with:
#   bash scripts/verify_m007_guard_gate.sh

set -euo pipefail

phase() {
  printf '\n== %s ==\n' "$1"
}

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "required tracked input is missing: $path"
}

require_nimble_wiring() {
  local test_name="$1"
  if ! grep -Fq "$test_name" gene.nimble; then
    fail "gene.nimble is missing test wiring: $test_name"
  fi
}

# Repository-root preflight: this script intentionally keeps all repository
# paths root-relative so missing tracked inputs fail before long-running checks.
phase "Preflight: root-relative tracked inputs"
require_file "gene.nimble"
require_file "src/gene/types/runtime_types.nim"
require_file "src/gene/vm/args.nim"
require_file "src/gene/vm/core_helpers.nim"
require_file "src/gene/vm/exec.nim"
require_file "tests/test_runtime_guard_contract.nim"
require_file "tests/test_strict_nil_policy.nim"
require_file "tests/integration/test_cli_gir.nim"
require_file "tests/integration/test_callable_guard_blame.nim"
require_file "tests/integration/test_local_property_guard_blame.nim"
require_file "tests/integration/test_enum_payload_guard_blame.nim"
require_file "tests/integration/test_strict_nil_cli.nim"
require_file "testsuite/run_tests.sh"
require_file "testsuite/02-types/types/20_strict_nil_policy.gene"
require_file "testsuite/02-types/types/21_callable_guard_blame.gene"
require_file "testsuite/02-types/types/22_local_property_guard_blame.gene"
require_file "testsuite/02-types/types/23_enum_payload_guard_blame.gene"

phase "Preflight: gene.nimble guard test wiring"
require_nimble_wiring "test_runtime_guard_contract"
require_nimble_wiring "test_callable_guard_blame"
require_nimble_wiring "test_local_property_guard_blame"
require_nimble_wiring "test_enum_payload_guard_blame"
require_nimble_wiring "test_strict_nil_cli"

# Build before any CLI or testsuite invocation so stale bin/gene cannot satisfy
# the runtime guard migration gate.
phase "Build: fresh gene binary"
run nimble build
[[ -x "bin/gene" ]] || fail "nimble build completed but bin/gene is not executable"

phase "Internal guard contract"
run nim c -r tests/test_runtime_guard_contract.nim

phase "Strict nil unit policy"
run nim c -r tests/test_strict_nil_policy.nim

phase "CLI/GIR guard surfaces"
run nim c -r tests/integration/test_cli_gir.nim

phase "Callable guard blame"
run nim c -r tests/integration/test_callable_guard_blame.nim

phase "Local/property guard blame"
run nim c -r tests/integration/test_local_property_guard_blame.nim

phase "Enum-payload guard blame"
run nim c -r tests/integration/test_enum_payload_guard_blame.nim

phase "Strict nil CLI regressions"
run nim c -r tests/integration/test_strict_nil_cli.nim

phase "Selected M007 testsuite fixtures"
run ./testsuite/run_tests.sh \
  02-types/types/20_strict_nil_policy.gene \
  02-types/types/21_callable_guard_blame.gene \
  02-types/types/22_local_property_guard_blame.gene \
  02-types/types/23_enum_payload_guard_blame.gene

phase "Full testsuite"
run ./testsuite/run_tests.sh

printf '\nM007 guard gate passed.\n'
