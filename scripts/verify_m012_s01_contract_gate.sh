#!/usr/bin/env bash
# Repeatable M012/S01 unified filesystem serializer contract gate.
# Run from the repository root with:
#   bash scripts/verify_m012_s01_contract_gate.sh

set -euo pipefail

current_phase="startup"

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

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is missing from PATH: $tool"
}

require_tracked_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "required S01 artifact is missing: $path"
  git ls-files --error-unmatch "$path" >/dev/null 2>&1 || fail "required S01 artifact is not tracked by git: $path"
}

change_id="replace-tree-serdes-with-file-refs"
change_dir="openspec/changes/$change_id"

required_files=(
  "$change_dir/proposal.md"
  "$change_dir/design.md"
  "$change_dir/tasks.md"
  "$change_dir/specs/filesystem-serdes/spec.md"
  "spec/15-serialization.md"
)

wording_roots=(
  "$change_dir"
  "spec/15-serialization.md"
)

protected_paths=(
  "src/gene/serdes.nim"
  "example-projects/geneclaw/src/home_store.gene"
  "tests"
  "testsuite"
)

phase "Preflight: root-relative tracked S01 artifacts"
require_tool bash
require_tool git
require_tool openspec
require_tool python3
for path in "${required_files[@]}"; do
  require_tracked_file "$path"
done

phase "OpenSpec strict validation"
run openspec validate "$change_id" --strict

phase "Public wording: old tree API only in removal/migration context"
python3 - "${wording_roots[@]}" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

roots = sys.argv[1:]
old_api = re.compile(r"\b(?:read_tree|write_tree)\b")
allowed_context = re.compile(
    r"remove|removed|removal|removing|retire|retired|superseded|prior[- ]art|"
    r"migration|migrate|not appear|shall not|must not|should not|not remain|"
    r"not be exported|not exported|not compatibility|not compatibility aliases|"
    r"non-goals?|violates?|conflicts?|earlier filesystem|earlier drafts|"
    r"current(?:ly)? has|old tree-serdes|removal targets?|breaking|unsupported|"
    r"replaced|replace|no longer|compatibility layer",
    re.IGNORECASE,
)

def tracked_files_for(root: str) -> list[str]:
    args = ["git", "ls-files", "--", root]
    result = subprocess.run(args, check=True, text=True, capture_output=True)
    return [line for line in result.stdout.splitlines() if line.endswith(".md")]

files: list[str] = []
for root in roots:
    files.extend(tracked_files_for(root))
files = sorted(dict.fromkeys(files))
if not files:
    raise SystemExit("no tracked markdown files found for wording scan")

violations: list[str] = []
mentions = 0
for file_name in files:
    path = Path(file_name)
    lines = path.read_text(encoding="utf-8").splitlines()
    in_fence = False
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
        if not old_api.search(line):
            continue
        mentions += 1
        if in_fence:
            violations.append(
                f"{file_name}:{index + 1}: old tree API appears inside a code block/live example: {line.strip()}"
            )
            continue
        window_start = max(0, index - 2)
        window_end = min(len(lines), index + 3)
        context = "\n".join(lines[window_start:window_end])
        if not allowed_context.search(context):
            violations.append(
                f"{file_name}:{index + 1}: old tree API mention lacks removal/migration/superseded context: {line.strip()}"
            )

if violations:
    print("Old tree API wording violations:", file=sys.stderr)
    for violation in violations:
        print(f"  - {violation}", file=sys.stderr)
    raise SystemExit(1)

print(f"Checked {len(files)} tracked markdown files; {mentions} old tree API mentions are removal/migration/superseded context only.")
PY

phase "Scope isolation: no S01 implementation/test surface edits"
protected_diff="$(git diff --name-only HEAD -- "${protected_paths[@]}")"
if [[ -n "$protected_diff" ]]; then
  printf 'Protected implementation/test paths changed during S01:\n%s\n' "$protected_diff" >&2
  fail "S01 must not modify serdes runtime, GeneClaw storage, tests, or testsuite fixtures"
fi
printf 'No protected implementation/test path changes detected.\n'

printf '\nM012/S01 contract gate passed.\n'
