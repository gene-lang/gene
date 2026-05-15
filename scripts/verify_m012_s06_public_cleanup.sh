#!/usr/bin/env bash
# Repeatable M012/S06 public cleanup gate for unified filesystem serialization.
# Run from the repository root with:
#   bash scripts/verify_m012_s06_public_cleanup.sh

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

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is missing from PATH: $tool"
}

phase "Preflight"
require_tool git
require_tool python3
git rev-parse --show-toplevel >/dev/null 2>&1 || fail "must be run inside the Gene repository"

phase "Public cleanup scan"
python3 <<'PY'
from __future__ import annotations

import re
import subprocess
from pathlib import Path

PUBLIC_ROOTS = [
    "docs",
    "spec",
    "openspec/changes/replace-tree-serdes-with-file-refs",
    "examples",
    "example-projects/geneclaw",
    "tests",
    "testsuite",
]
TEXT_SUFFIXES = {
    ".md", ".gene", ".nim", ".sh", ".py", ".txt", ".json", ".yaml", ".yml"
}

OLD_TREE_API = re.compile(r"\b(?:read_tree|write_tree)\b")
OLD_GENECLAW_HELPERS = re.compile(r"\b(?:read_tree_or_default|write_record_tree|tree_exists\?)\b")
OLD_SEPARATE_OPTION = re.compile(r"\^separate\b")
UNSUPPORTED_READ_DIR = re.compile(
    r"\bread_dir\b[^\n]*(?:\^lazy\s+true|\^order\s+(?:\"ctime\"|ctime|\^ctime))"
)

REMOVAL_OR_PRIOR_ART = re.compile(
    r"remove|removed|removal|removing|retire|retired|superseded|prior[- ]art|"
    r"migration|migrate|non-goals?|not appear|shall not|must not|should not|not remain|"
    r"not be exported|not exported|compatibility aliases|not compatibility|not compatibility aliases|"
    r"old tree-serdes|earlier filesystem|earlier drafts|historical tree-serdes|"
    r"replaced|replace|no longer|breaking|unsupported|reject|rejected|fail(?:ed|s|ure|-closed)?|"
    r"negative|diagnostic|leak|leaks|omits|not contain|violates?|conflicts?",
    re.IGNORECASE,
)

NEGATIVE_TEST_PATHS = (
    "tests/integration/test_filesystem_serdes_api_removal.nim",
    "tests/integration/test_filesystem_serdes_identity.nim",
    "tests/integration/test_filesystem_serdes_lazy_refs.nim",
    "tests/integration/test_filesystem_serdes_read_refs.nim",
    "tests/integration/test_filesystem_serdes_write_refs.nim",
)

GENECLAW_LIVE_ROOTS = ["example-projects/geneclaw/src", "example-projects/geneclaw/tests"]
GENECLAW_OLD_TERMS = re.compile(
    r"gene/serdes/(?:read_tree|write_tree)|\^separate\b|"
    r"\b(?:read_tree_or_default|write_record_tree|tree_exists\?)\b"
)


def tracked_files(*roots: str) -> list[str]:
    output = subprocess.check_output(["git", "ls-files", "--", *roots], text=True)
    files: list[str] = []
    for name in output.splitlines():
        path = Path(name)
        if path.suffix in TEXT_SUFFIXES:
            files.append(name)
    return sorted(dict.fromkeys(files))


def read_lines(path: str) -> list[str]:
    try:
        return Path(path).read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return []


def context(lines: list[str], index: int, radius: int = 2) -> str:
    start = max(0, index - radius)
    end = min(len(lines), index + radius + 1)
    return "\n".join(lines[start:end])


def in_markdown_fence(lines: list[str], index: int) -> bool:
    in_fence = False
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
        if i == index:
            return in_fence
    return False


def allowed_old_tree_context(path: str, lines: list[str], index: int) -> bool:
    window = context(lines, index)
    if not REMOVAL_OR_PRIOR_ART.search(window):
        return False
    if in_markdown_fence(lines, index):
        # Old API names inside docs/spec code blocks look like live examples. Tests
        # may include failing fixture strings, but trunk docs must keep them prose-only.
        return path in NEGATIVE_TEST_PATHS
    return True


def allowed_old_separate_context(path: str, lines: list[str], index: int) -> bool:
    window = context(lines, index)
    if path in NEGATIVE_TEST_PATHS and REMOVAL_OR_PRIOR_ART.search(window):
        return True
    if path.endswith("/design.md") and REMOVAL_OR_PRIOR_ART.search(window):
        return True
    return False


def allowed_unsupported_read_dir_context(path: str, lines: list[str], index: int) -> bool:
    if path in NEGATIVE_TEST_PATHS:
        return True
    window = context(lines, index)
    if not REMOVAL_OR_PRIOR_ART.search(window):
        return False
    if path.startswith("openspec/changes/replace-tree-serdes-with-file-refs/"):
        return True
    if path.startswith("docs/") or path.startswith("spec/"):
        return True
    return False


def check_repository() -> list[str]:
    violations: list[str] = []

    # GeneClaw live helpers should have no old terms at all; these are runtime
    # fixtures/helpers, not migration prose.
    for path in tracked_files(*GENECLAW_LIVE_ROOTS):
        for lineno, line in enumerate(read_lines(path), 1):
            if GENECLAW_OLD_TERMS.search(line):
                violations.append(f"{path}:{lineno}: GeneClaw live old serializer term: {line.strip()}")

    for path in tracked_files(*PUBLIC_ROOTS):
        lines = read_lines(path)
        for index, line in enumerate(lines):
            lineno = index + 1
            if OLD_GENECLAW_HELPERS.search(line):
                violations.append(f"{path}:{lineno}: old GeneClaw helper name outside live API: {line.strip()}")
            if OLD_TREE_API.search(line) and not allowed_old_tree_context(path, lines, index):
                violations.append(f"{path}:{lineno}: unallowlisted read_tree/write_tree reference: {line.strip()}")
            if OLD_SEPARATE_OPTION.search(line) and not allowed_old_separate_context(path, lines, index):
                violations.append(f"{path}:{lineno}: unallowlisted ^separate reference: {line.strip()}")
            if UNSUPPORTED_READ_DIR.search(line) and not allowed_unsupported_read_dir_context(path, lines, index):
                violations.append(f"{path}:{lineno}: unsupported read_dir option taught outside negative/future context: {line.strip()}")

    return violations


def self_test() -> None:
    live_doc = ["Use (gene/serdes/read_tree \"state\") in your app."]
    if allowed_old_tree_context("docs/live.md", live_doc, 0):
        raise AssertionError("live read_tree example should be rejected")

    live_write = ["Call (gene/serdes/write \"root.gene\" v ^separate [/items])."]
    if allowed_old_separate_context("docs/live.md", live_write, 0):
        raise AssertionError("live ^separate example should be rejected")

    live_lazy_dir = ["Call (gene/serdes/read_dir \"items\" ^shape array ^order name ^lazy true)."]
    if allowed_unsupported_read_dir_context("docs/live.md", live_lazy_dir, 0):
        raise AssertionError("live read_dir ^lazy true example should be rejected")

    live_ctime = ["Call (gene/serdes/read_dir \"items\" ^shape array ^order ctime)."]
    if allowed_unsupported_read_dir_context("docs/live.md", live_ctime, 0):
        raise AssertionError("live read_dir ^order ctime example should be rejected")

    prior_art = ["Earlier filesystem drafts removed read_tree and write_tree as superseded prior-art names."]
    if not allowed_old_tree_context("spec/15-serialization.md", prior_art, 0):
        raise AssertionError("removal/prior-art old API mention should be allowed")

    negative_test = ["test rejects read_dir ^lazy true", "expect_error('(gene/serdes/read_dir \"x\" ^lazy true)')"]
    if not allowed_unsupported_read_dir_context("tests/integration/test_filesystem_serdes_lazy_refs.nim", negative_test, 1):
        raise AssertionError("negative read_dir lazy test should be allowed")


self_test()
violations = check_repository()
if violations:
    print("Public cleanup violations:", file=__import__("sys").stderr)
    for violation in violations:
        print(f"  - {violation}", file=__import__("sys").stderr)
    raise SystemExit(1)

print("Public cleanup scan passed: unified filesystem serializer docs/specs/examples/tests contain only supported live API teaching.")
PY

printf '\nM012/S06 public cleanup gate passed.\n'
