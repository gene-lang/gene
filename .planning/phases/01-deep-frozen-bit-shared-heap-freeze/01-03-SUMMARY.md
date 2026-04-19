---
phase: 01-deep-frozen-bit-shared-heap-freeze
plan: 03
subsystem: runtime
tags: [nim, vm, freeze, deep-frozen, bytecode, testing]
requires:
  - phase: 01-01
    provides: deep_frozen/shared header accessors and bit setters
provides:
  - Typed deep-frozen write helper for mutation guards
  - VM opcode guards for deep-frozen map, gene, array, and instance writes
  - Regression coverage for guarded mutation opcode paths
affects: [phase-01-freeze-runtime, actor-runtime, mutation-semantics]
tech-stack:
  added: []
  patterns: [typed runtime write guard, opcode-level mutation regression harness]
key-files:
  created: [tests/test_phase1_frozen_write_guard.nim]
  modified: [src/gene/types/core/value_ops.nim, src/gene/vm/exec.nim]
key-decisions:
  - "Guard the actual mutation opcode handlers in exec.nim, including current-map/current-gene builder opcodes, instead of relying on higher-level surface syntax alone."
  - "Keep the existing shallow frozen checks intact and add deep-frozen guards ahead of the writes."
patterns-established:
  - "Any new in-place VM mutator must call the deep-frozen guard before writing into a managed target."
  - "Opcode regressions can use manual CompilationUnit/VM harnesses when surface syntax does not map 1:1 to the handler being verified."
requirements-completed: [FRZ-03, FRZ-04]
duration: 25m
completed: 2026-04-18
---

# Phase 1 Plan 03: Mutation opcode guards summary

**Typed deep-frozen mutation guards across the VM’s managed write opcodes with opcode-level regression coverage and a clean Phase 0 acceptance sweep**

## Performance

- **Duration:** 25m
- **Started:** 2026-04-19T00:12:00Z
- **Completed:** 2026-04-19T00:36:36Z
- **Tasks:** 4
- **Files modified:** 3

## Accomplishments

- Added `FrozenWriteError` and `raise_frozen_write` so deep-frozen writes fail with an opcode-specific runtime message and typed payload.
- Guarded every audited in-place mutator in `exec.nim`, including direct target setters plus current-map/current-gene builder opcodes.
- Added a manual-bytecode regression harness that exercises each guarded opcode path directly.
- Ran the plan verification plus the Phase 0 acceptance sweep with no new failures.

## Task Commits

1. **T1-T4: helper, opcode guards, tests, verification** - `9055ef9` (`feat`)

## Files Created/Modified

- `src/gene/types/core/value_ops.nim` - Defines `FrozenWriteError` and `raise_frozen_write`.
- `src/gene/vm/exec.nim` - Inserts deep-frozen guards ahead of audited in-place mutation writes.
- `tests/test_phase1_frozen_write_guard.nim` - Manual VM/bytecode regression harness for every guarded opcode path.

## Guarded Opcode Inventory

- `IkSetMember` map/gene/instance writes at `src/gene/vm/exec.nim:717`, `src/gene/vm/exec.nim:721`, `src/gene/vm/exec.nim:729`
- `IkSetMemberDynamic` map/instance/gene/array writes at `src/gene/vm/exec.nim:774`, `src/gene/vm/exec.nim:782`, `src/gene/vm/exec.nim:791`, `src/gene/vm/exec.nim:811`
- `IkSetChild` array/gene writes at `src/gene/vm/exec.nim:1345`, `src/gene/vm/exec.nim:1352`
- `IkMapSetProp`, `IkMapSetPropValue`, `IkMapSpread` at `src/gene/vm/exec.nim:1659`, `src/gene/vm/exec.nim:1665`, `src/gene/vm/exec.nim:1673`
- `IkGeneSetType`, `IkGeneSetProp` at `src/gene/vm/exec.nim:1965`, `src/gene/vm/exec.nim:1976`
- `IkGeneAddChild`, `IkGeneAdd`, `IkGeneAddSpread`, `IkGeneAddChildValue` at `src/gene/vm/exec.nim:2025`, `src/gene/vm/exec.nim:2060`, `src/gene/vm/exec.nim:2093`, `src/gene/vm/exec.nim:2123`
- Frame/native-frame gene-arg mutations are guarded for `IkGeneSetProp`, `IkGeneAddChild`, `IkGeneAdd`, `IkGeneAddSpread`, `IkGeneAddChildValue`, `IkGeneSetPropValue`, and `IkGenePropsSpread` at `src/gene/vm/exec.nim:1981`, `src/gene/vm/exec.nim:1987`, `src/gene/vm/exec.nim:2014`, `src/gene/vm/exec.nim:2022`, `src/gene/vm/exec.nim:2049`, `src/gene/vm/exec.nim:2057`, `src/gene/vm/exec.nim:2080`, `src/gene/vm/exec.nim:2089`, `src/gene/vm/exec.nim:2112`, `src/gene/vm/exec.nim:2120`, `src/gene/vm/exec.nim:2140`, `src/gene/vm/exec.nim:2164`
- `IkGeneSetPropValue` and `IkGenePropsSpread` direct gene writes at `src/gene/vm/exec.nim:2136`, `src/gene/vm/exec.nim:2159`
- Typed helper entrypoints at `src/gene/types/core/value_ops.nim:41`, `src/gene/types/core/value_ops.nim:45`

## Test Evidence

- The typed helper payload is checked directly in `tests/test_phase1_frozen_write_guard.nim:51-61` via `raise_frozen_write("IkSetMember", target)`.
- `IkSetMember` paths are covered at `tests/test_phase1_frozen_write_guard.nim:70-91`.
- `IkSetMemberDynamic` paths are covered at `tests/test_phase1_frozen_write_guard.nim:97-132`.
- `IkSetChild` paths are covered at `tests/test_phase1_frozen_write_guard.nim:138-151`.
- `IkMapSetProp`, `IkMapSetPropValue`, and `IkMapSpread` are covered at `tests/test_phase1_frozen_write_guard.nim:157-178`.
- `IkGeneSetType`, `IkGeneSetProp`, `IkGeneAddChild`, `IkGeneAdd`, `IkGeneAddSpread`, `IkGeneAddChildValue`, `IkGeneSetPropValue`, and `IkGenePropsSpread` are covered at `tests/test_phase1_frozen_write_guard.nim:184-250`.

## Verification

- `nim check src/gene.nim` — PASS
- `nim c -r tests/test_phase1_frozen_write_guard.nim` — PASS
- `nim c -r tests/test_bootstrap_publication.nim` — PASS
- `nim c -r tests/integration/test_scope_lifetime.nim` — PASS
- `nim c -r tests/integration/test_cli_gir.nim` — PASS
- `nim c -r tests/integration/test_thread.nim` — PASS
- `nim c -r tests/integration/test_stdlib_string.nim` — PASS
- `nim c -r tests/test_native_trampoline.nim` — PASS
- `./testsuite/run_tests.sh` — PASS

## Decisions Made

- Guarded the current-map and current-gene builder opcodes because they are the codebase’s real equivalents of the plan’s generic map/gene mutation inventory.
- Added the guard before each write while leaving the shallow `frozen` checks untouched so Phase 1 semantics stay additive.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Adjusted opcode-path assertions to match VM exception normalization**
- **Found during:** Task 3 (regression test implementation)
- **Issue:** `exec()` wraps Nim `CatchableError` values into Gene runtime exceptions before they leave the VM, so opcode-path tests cannot directly catch `FrozenWriteError`.
- **Fix:** Opcode-path tests assert the surfaced deep-frozen mutation message, and a direct helper test verifies `FrozenWriteError.target_kind` plus `.op`.
- **Files modified:** `tests/test_phase1_frozen_write_guard.nim`
- **Verification:** `nim c -r tests/test_phase1_frozen_write_guard.nim`
- **Committed in:** `9055ef9`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No runtime scope creep. The implementation still raises `FrozenWriteError` internally; the test adapts to existing VM exception normalization.

## Issues Encountered

- None beyond the existing runtime exception wrapper behavior already captured as a deviation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Deep-frozen mutation writes now fail deterministically across the audited VM opcode inventory.
- Phase 1 freeze/tagging work can rely on these guards without changing shallow frozen semantics.

## Known Stubs

None.

## Self-Check

PASSED

- Found `.planning/phases/01-deep-frozen-bit-shared-heap-freeze/01-03-SUMMARY.md`
- Found implementation commit `9055ef9`

---
*Phase: 01-deep-frozen-bit-shared-heap-freeze*
*Completed: 2026-04-18*
