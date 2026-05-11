#!/usr/bin/env bash
# Repeatable M009/S05 Explicit Runtime Interception Beta gate.
# Run from the repository root with:
#   bash scripts/verify_m009_interception_beta_gate.sh
# The expensive final regression phase is intentionally separable:
#   ./testsuite/run_tests.sh

set -euo pipefail

current_phase="startup"

usage() {
  cat <<'USAGE'
Usage: bash scripts/verify_m009_interception_beta_gate.sh [mode]

Modes:
  --help                    Show this help text.
  --include-full-testsuite  Run the fast Beta gate, then run ./testsuite/run_tests.sh.
  --full-suite-only         Run only the final ./testsuite/run_tests.sh phase.

Default mode runs the fast Beta gate only: fresh nimble build, focused
function/class interception fixtures, public-surface assertions, OpenSpec strict
validation, interception example semantic-marker checks, and examples runner.
After default mode passes, run the final required phase separately:
  ./testsuite/run_tests.sh
USAGE
}

on_error() {
  local status="$?"
  printf 'ERROR: phase failed (%s), exit code %s\n' "$current_phase" "$status" >&2
  exit "$status"
}
trap on_error ERR

phase() {
  current_phase="$1"
  printf '\n== %s ==\n' "$1"
}

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

run_capture() {
  local output="$1"
  shift
  printf '+ '
  printf '%q ' "$@"
  printf '> %q 2>&1\n' "$output"
  "$@" >"$output" 2>&1
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "required tracked input is missing: $path"
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is missing from PATH: $tool"
}

require_output_line() {
  local file="$1"
  local expected_line="$2"
  if ! grep -Fxq -- "$expected_line" "$file"; then
    printf 'Missing expected output line in %s: %s\n' "$file" "$expected_line" >&2
    printf '%s\n' '--- captured output (truncated to 4000 bytes) ---' >&2
    python3 - "$file" <<'PY' >&2
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='replace') as handle:
    print(handle.read(4000))
PY
    printf '%s\n' '--- end captured output ---' >&2
    exit 1
  fi
}

include_full_testsuite=false
full_suite_only=false

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      usage
      exit 0
      ;;
    --include-full-testsuite)
      include_full_testsuite=true
      ;;
    --full-suite-only)
      full_suite_only=true
      ;;
    *)
      fail "unknown argument: $arg"
      ;;
  esac
done

if [[ "$include_full_testsuite" == true && "$full_suite_only" == true ]]; then
  fail "choose only one of --include-full-testsuite or --full-suite-only"
fi

focused_fixtures=(
  testsuite/05-functions/functions/11_interception_function_boundaries.gene
  testsuite/05-functions/functions/14_fn_interceptor_callable_wrapper.gene
  testsuite/05-functions/functions/15_fn_interceptor_boundaries.gene
  testsuite/05-functions/functions/16_fn_interceptor_enablement.gene
  testsuite/05-functions/functions/17_fn_interceptor_diagnostics.gene
  testsuite/05-functions/functions/18_fn_interceptor_call_shapes.gene
  testsuite/07-oop/oop/10_interception_controls_and_legacy_removal.gene
  testsuite/07-oop/oop/11_interceptor_callable_class.gene
  testsuite/07-oop/oop/12_interceptor_enablement.gene
  testsuite/07-oop/oop/13_interceptor_diagnostics.gene
  testsuite/07-oop/oop/14_interceptor_call_shapes.gene
)

public_surface_files=(
  testsuite/experimental/interception_public_surface_assertions.py
  docs/interception.md
  docs/feature-status.md
  docs/README.md
  docs/architecture.md
  testsuite/README.md
  examples/interception.gene
  examples/README.md
  examples/run_examples.sh
  openspec/changes/add-class-aspects/proposal.md
  openspec/changes/add-class-aspects/design.md
  openspec/changes/add-class-aspects/tasks.md
  openspec/changes/add-class-aspects/specs/explicit-interception/spec.md
)

example_files=(
  examples/hello_world.gene
  examples/print.gene
  examples/cmd_args.gene
  examples/env.gene
  examples/json.gene
  examples/datetime.gene
  examples/fib.gene
  examples/async.gene
  examples/io.gene
  examples/oop.gene
  examples/interception.gene
  examples/sample_typed.gene
  examples/process_management.gene
)

full_suite_files=(
  testsuite/run_tests.sh
  testsuite/pipe/run_tests.sh
  testsuite/examples/run_tests.sh
)

example_semantic_markers=(
  '=== Beta explicit class interception ==='
  'class direct keyword result 15'
  'class positional spread result 24'
  'class keyword spread result 41'
  'class combined spread result 55'
  '=== Beta explicit function interception ==='
  'function original unchanged result 6'
  'function wrapper direct keyword result 8'
  'function wrapper positional spread result 9'
  'function wrapper keyword spread result 12'
  'function wrapper combined spread result 15'
  'function wrapper disabled result 12'
  'function wrapper reenabled result 14'
)

preflight_common() {
  require_tool bash
  require_tool grep
  require_tool nimble
  require_tool openspec
  require_tool python3
  require_file gene.nimble
  require_file src/gene.nim
}

preflight_fast_gate() {
  local path
  for path in "${focused_fixtures[@]}"; do
    require_file "$path"
  done
  for path in "${public_surface_files[@]}"; do
    require_file "$path"
  done
  for path in "${example_files[@]}"; do
    require_file "$path"
  done
}

preflight_full_suite() {
  local path
  for path in "${full_suite_files[@]}"; do
    require_file "$path"
  done
}

build_gene() {
  phase "Build: fresh gene binary"
  run nimble build
  [[ -x bin/gene ]] || fail "nimble build completed but bin/gene is not executable"
}

run_focused_fixtures() {
  phase "Focused function/class interception fixtures"
  run ./testsuite/run_tests.sh "${focused_fixtures[@]}"
}

run_public_surface_assertions() {
  phase "Public-surface assertions"
  run python3 testsuite/experimental/interception_public_surface_assertions.py
}

run_openspec_validation() {
  phase "OpenSpec strict validation"
  run openspec validate add-class-aspects --strict
}

run_example_marker_checks() {
  phase "Interception example semantic markers"
  local output="$workdir/interception_example.out"
  run_capture "$output" ./bin/gene run examples/interception.gene

  local marker_count=0
  local marker
  for marker in "${example_semantic_markers[@]}"; do
    require_output_line "$output" "$marker"
    marker_count=$((marker_count + 1))
  done
  printf 'Verified %d interception example semantic markers.\n' "$marker_count"
}

run_examples() {
  phase "Examples runner"
  run bash examples/run_examples.sh
}

run_full_testsuite() {
  phase "Full testsuite"
  printf 'If command-suite failures occur, rerun testsuite/pipe/run_tests.sh or testsuite/examples/run_tests.sh as named by testsuite output.\n'
  run ./testsuite/run_tests.sh
}

print_deferred_full_testsuite() {
  phase "Full testsuite deferred"
  printf 'Fast Beta gate passed. Final required phase is intentionally separate for GSD timeout hygiene.\n'
  printf '+ ./testsuite/run_tests.sh\n'
}

phase "Preflight: root-relative tracked inputs"
preflight_common
preflight_full_suite
if [[ "$full_suite_only" != true ]]; then
  preflight_fast_gate
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/gene_m009_interception_beta_gate.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

build_gene

if [[ "$full_suite_only" == true ]]; then
  run_full_testsuite
  printf '\nM009 full testsuite phase passed.\n'
  exit 0
fi

run_focused_fixtures
run_public_surface_assertions
run_openspec_validation
run_example_marker_checks
run_examples

if [[ "$include_full_testsuite" == true ]]; then
  run_full_testsuite
else
  print_deferred_full_testsuite
fi

printf '\nM009 interception Beta fast gate passed.\n'
