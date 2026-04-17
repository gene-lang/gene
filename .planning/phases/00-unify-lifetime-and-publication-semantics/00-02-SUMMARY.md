---
phase: 00-unify-lifetime-and-publication-semantics
plan: 02
subsystem: infra
tags: [publication, gir, native, inline-cache, compiler]
requires:
  - phase: 00-01
    provides: "Stable lifetime assumptions at the runtime boundary"
provides:
  - Compilation units now publish with pre-sized inline caches across compile, compile_init, and GIR load paths
  - Lazy function/block body compilation is serialized behind a shared body-publication lock
  - Native code publication now sets entry/descriptor metadata before flipping native_ready
affects: [phase-0, compiler, gir, native-runtime, dispatch]
tech-stack:
  added: []
  patterns:
    - "Published compilation units must satisfy inline_caches.len == instructions.len"
    - "Lazy body publication and native publication use explicit locks instead of scattered unsynchronized writes"
key-files:
  created: []
  modified:
    - src/gene/types/helpers.nim
    - src/gene/compiler.nim
    - src/gene/compiler/pipeline.nim
    - src/gene/gir.nim
    - src/gene/vm/exec.nim
    - src/gene/vm/native.nim
    - src/gene/vm.nim
    - tests/integration/test_cli_gir.nim
key-decisions:
  - "Used explicit publication locks rather than broad eager compilation"
  - "Kept the inline cache invariant strict by removing hot-path growth and failing on unpublished units"
patterns-established:
  - "compile, compile_init, and load_gir are all publication surfaces and must initialize inline caches before runtime use"
  - "native_ready is the final publish step after all native metadata is installed"
requirements-completed: [PUB-01, PUB-02, PUB-03]
duration: unknown
completed: 2026-04-17
---

# Phase 0 / Plan 00-02 Summary

**Compilation units and native entry points now publish through explicit guarded paths instead of ad hoc runtime mutation**

## Performance

- **Duration:** not recorded
- **Started:** 2026-04-17
- **Completed:** 2026-04-17
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- Removed on-demand inline-cache growth from the VM hot path and enforced a published-CU invariant.
- Serialized lazy `body_compiled` publication for functions and blocks.
- Serialized native publication so `native_ready` only flips after entry/descriptor metadata is installed.
- Added GIR/lazy-hook assertions that compiled bodies and loaded units have inline caches sized at publish time.

## Task Commits

None - changes are currently uncommitted in the working tree.

## Files Created/Modified
- `src/gene/types/helpers.nim` - Added shared publication locks plus helper routines for inline-cache readiness and compiled-body publication.
- `src/gene/compiler.nim` - Guarded function/block lazy compilation behind the body-publication lock.
- `src/gene/compiler/pipeline.nim` - Made `compile_init` publish pre-sized inline caches.
- `src/gene/gir.nim` - Sized inline caches immediately on GIR load.
- `src/gene/vm/exec.nim` - Removed inline-cache growth fallback and routed compiled-body publication through helper logic.
- `src/gene/vm/native.nim` - Serialized native publication and made `native_ready` the final visible publish step.
- `src/gene/vm.nim` - Brought lock primitives into the VM include surface.
- `tests/integration/test_cli_gir.nim` - Added assertions for inline-cache sizing on GIR load and lazy runtime hook publication.

## Decisions Made
- Publication safety was enforced with explicit locks instead of flipping everything to eager compilation.
- The inline-cache invariant is now strict: published units must arrive ready, and runtime no longer repairs them opportunistically.

## Deviations from Plan

### Auto-fixed Issues

**1. compile_init was still publishing cache-less units**
- **Found during:** Verification after the first publication patch
- **Issue:** Worker-thread tests still failed because `compile_init` did not size `inline_caches`, even though `compile` and `load_gir` did.
- **Fix:** Added `inline_caches.setLen(instructions.len)` to `compile_init`.
- **Files modified:** `src/gene/compiler/pipeline.nim`
- **Verification:** Thread, GIR, native, and string regression suites all passed afterward.

---

**Total deviations:** 1 auto-fixed
**Impact on plan:** Tightened the intended invariant instead of weakening the new runtime assertion.

## Issues Encountered

The first strict inline-cache assertion exposed a real missed publication surface in `compile_init`. Fixing that source was cleaner than relaxing the invariant or restoring runtime growth.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Publication safety is now materially tighter across compiler, GIR, and native runtime boundaries. The major remaining Phase 0 work is still `00-01` (RC unification) and `00-05` (bootstrap publication discipline plus sweep).

---
*Phase: 00-unify-lifetime-and-publication-semantics*
*Completed: 2026-04-17*
