---
phase: 01-deep-frozen-bit-shared-heap-freeze
plan: 06
subsystem: docs-runtime
tags: [freeze, sealed, frozen, docs, errors, nim]
requires:
  - phase: 01-deep-frozen-bit-shared-heap-freeze
    provides: "(freeze v) entry point and FreezeScopeError from 01-02"
  - phase: 01-deep-frozen-bit-shared-heap-freeze
    provides: "Deep-frozen write guard surface from 01-03"
provides:
  - "User-facing Phase 1 terminology is finalized as sealed (shallow literals) vs frozen (deep `(freeze v)` graphs)"
  - "A new handbook entry explains the distinction, MVP freeze scope, and the Phase 1.5 closure follow-up"
  - "Regression assertions now check the renamed error text without weakening coverage"
affects: [phase-1, docs, freeze-runtime, error-messages]
tech-stack:
  added: []
  patterns:
    - "Keep the on-disk `frozen` field untouched while renaming only user-facing text to sealed/frozen"
    - "Update only exact error-string assertions when terminology changes"
key-files:
  created:
    - docs/handbook/freeze.md
  modified:
    - docs/proposals/actor-design.md
    - src/gene/stdlib/freeze.nim
    - src/gene/types/core/value_ops.nim
    - tests/test_phase1_frozen_write_guard.nim
    - tests/integration/test_stdlib_array.nim
    - tests/integration/test_stdlib_map.nim
    - tests/integration/test_stdlib_gene.nim
key-decisions:
  - "Kept the runtime field/storage names unchanged and limited the naming sweep to docs, doc comments, and user-visible error strings"
  - "Left the handbook page unlinked because no handbook index exists under `docs/` yet"
requirements-completed: [NAME-01]
completed: 2026-04-18
---

# Phase 1 / Plan 01-06 Summary

**Phase 1 now uses `sealed` for shallow `#[]` / `#{}` / `#()` values and `frozen` for deep `(freeze v)` output across the scoped runtime/docs surface, with a new handbook page and green regression sweeps**

## Accomplishments

- Updated `FreezeScopeError` and `FrozenWriteError` wording so deep `(freeze ...)` failures and deep write guards consistently say `frozen`.
- Updated the shallow literal write guards in `value_ops.nim` so user-facing errors say `sealed array`, `sealed map`, `sealed gene`, and `sealed hash map`.
- Reconciled `docs/proposals/actor-design.md` with the finalized D-13 glossary, including the tag-on-existing-heap Phase 1 semantics and the sealed/frozen split.
- Added [docs/handbook/freeze.md](/Users/gcao/gene-workspace/gene-old/docs/handbook/freeze.md) with the Phase 1 glossary, MVP scope, examples, and the Phase 1.5 closure forward reference.
- Updated only the tests that explicitly asserted the renamed error strings; assertion strength stayed equivalent because each test still checks the specific surfaced term.

## Audit Diff-Stat

```text
docs/proposals/actor-design.md           | 50 +++++++++++++++++---------------
src/gene/stdlib/freeze.nim               |  9 +++++-
src/gene/types/core/value_ops.nim        | 12 ++++----
docs/handbook/freeze.md                  | 116 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
tests/integration/test_stdlib_array.nim  |  6 ++--
tests/integration/test_stdlib_gene.nim   | 10 +++----
tests/integration/test_stdlib_map.nim    | 10 +++----
tests/test_phase1_frozen_write_guard.nim |  2 +-
```

## Terminology Outcome

- `sealed` now refers to the shallow literal form only.
- `frozen` now refers to `(freeze v)` output and deep write protection.
- The on-disk `frozen: bool` field is unchanged.
  Verification: there is no diff in `src/gene/types/type_defs.nim`, `src/gene/types/reference_types.nim`, or `src/gene/types/core/constructors.nim`.

## Handbook Note

- Handbook entry: [docs/handbook/freeze.md](/Users/gcao/gene-workspace/gene-old/docs/handbook/freeze.md)
- Length: 116 lines
- Link status: left unlinked because this repo does not currently have a `docs/handbook/` index to update

## Verification

- `nim check src/gene.nim` — PASS
- `nim c -r tests/test_phase1_header_bits.nim` — PASS
- `nim c -r tests/test_phase1_freeze_op.nim` — PASS
- `nim c -r tests/test_phase1_frozen_write_guard.nim` — PASS
- `nim c -r tests/test_phase1_rc_branch.nim` — PASS
- `nim c -d:release -r tests/test_phase1_rc_branch.nim` — PASS
- `nim c -r --mm:orc --threads:on tests/test_phase1_shared_heap.nim` — PASS
- `nim c --mm:orc --threads:on tests/test_phase1_shared_heap.nim` + 100 executions of `./tests/test_phase1_shared_heap` — PASS (`100/100`)
- `nim c -r --mm:orc --threads:on --passC:-fsanitize=thread --passL:-fsanitize=thread tests/test_phase1_shared_heap.nim` — PASS
- `nim c -r tests/test_bootstrap_publication.nim` — PASS
- `nim c -r tests/integration/test_scope_lifetime.nim` — PASS
- `nim c -r tests/integration/test_cli_gir.nim` — PASS
- `nim c -r tests/integration/test_thread.nim` — PASS
- `nim c -r tests/integration/test_stdlib_string.nim` — PASS
- `nim c -r tests/test_native_trampoline.nim` — PASS
- `./testsuite/run_tests.sh` — PASS (`132` passed, `0` failed)
- Manual doc review: read `docs/handbook/freeze.md` end to end and confirmed the sealed/frozen split is internally consistent

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated exact test assertions to match the renamed user-visible error text**
- **Found during:** Verification after the terminology sweep
- **Issue:** `tests/test_phase1_frozen_write_guard.nim`, `tests/integration/test_stdlib_array.nim`, `tests/integration/test_stdlib_map.nim`, and `tests/integration/test_stdlib_gene.nim` still asserted the old wording (`deep-frozen` / `immutable ...`), so the intended user-visible rename broke regression expectations.
- **Fix:** Updated only the exact string assertions to the new terms: `frozen ...` for deep write guards and `sealed ...` for shallow literal guards.
- **Files modified:** `tests/test_phase1_frozen_write_guard.nim`, `tests/integration/test_stdlib_array.nim`, `tests/integration/test_stdlib_map.nim`, `tests/integration/test_stdlib_gene.nim`
- **Verification:** Re-ran each affected focused test plus the full Phase 0 and Phase 1 sweeps listed above.
- **Coverage impact:** Equivalent strength. No assertion was weakened to a looser pattern than before; each still checks the specific surfaced term.

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No runtime scope creep. The only extra edits were the explicitly allowed test-string updates required by the renamed user-visible terminology.

## Known Stubs

None.

## Self-Check

PASSED

- Found [docs/handbook/freeze.md](/Users/gcao/gene-workspace/gene-old/docs/handbook/freeze.md)
- Confirmed the planned on-disk shallow field sites were not modified
- Confirmed the Phase 0 acceptance sweep and the relevant Phase 1 regression suites all passed
