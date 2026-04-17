---
phase: 00-unify-lifetime-and-publication-semantics
plan: 04
subsystem: infra
tags: [strings, immutability, vm, stdlib]
requires:
  - phase: 00-01
    provides: "Stable ownership groundwork for removing string-mutation special cases"
provides:
  - String.append returns a new string instead of mutating the receiver
  - Duplicate mutable-string helpers were removed from both stdlib string implementations
  - IkPushValue no longer copies string literals defensively
affects: [phase-0, string-runtime, stdlib, literal-loading]
tech-stack:
  added: []
  patterns:
    - "String transformations return new values instead of mutating receiver storage"
    - "VM literal loading can share string constants directly when runtime semantics are immutable"
key-files:
  created: []
  modified:
    - src/gene/stdlib/strings.nim
    - src/gene/stdlib/core.nim
    - src/gene/vm/exec.nim
    - tests/integration/test_stdlib_string.nim
key-decisions:
  - "Used return-new-string semantics for String.append instead of introducing StringBuilder in Phase 0"
  - "Removed the IkPushValue string copy because immutable append semantics make the old defensive path unnecessary"
patterns-established:
  - "String methods that conceptually transform data should return new string values"
  - "User-visible string API changes must be pinned by integration tests that verify alias safety"
requirements-completed: [STR-01, STR-02]
duration: unknown
completed: 2026-04-17
---

# Phase 0 / Plan 00-04 Summary

**String append now returns new values, and VM literal pushes no longer clone string constants for mutation safety**

## Performance

- **Duration:** not recorded
- **Started:** 2026-04-17
- **Completed:** 2026-04-17
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Switched both stdlib string implementations from in-place append mutation to return-new semantics.
- Deleted the `IkPushValue` string-copy special case because immutable strings no longer need per-binding cloning.
- Updated string integration coverage to assert alias-safe append behavior (`s` stays `"a"` while derived values grow).

## Task Commits

None - changes are currently uncommitted in the working tree.

## Files Created/Modified
- `src/gene/stdlib/strings.nim` - Removed mutable-string helper logic and made `append` build a new string value.
- `src/gene/stdlib/core.nim` - Mirrored the same immutable-string behavior in the alternate stdlib implementation.
- `src/gene/vm/exec.nim` - Simplified `IkPushValue` to push string literals directly.
- `tests/integration/test_stdlib_string.nim` - Replaced the old mutable-append expectation with alias-safe immutable append checks.

## Decisions Made
- Phase 0 uses return-new semantics for `String.append` rather than adding a new builder type.
- The VM now trusts string literals as shareable immutable values, so literal push no longer allocates a private copy.

## Deviations from Plan

None - plan executed as intended once the append behavior was confirmed to only affect the string integration suite in-tree.

## Issues Encountered

The main compatibility question was whether mutable `.append` behavior was relied on elsewhere in-tree. A targeted search found only the string integration test expecting that behavior, so the API cut stayed contained.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

String runtime semantics are now aligned with the actor-design Phase 0 direction. The remaining heavy Phase 0 work is still `00-01` (RC unification), `00-02` (publication safety), and `00-05` (bootstrap publication discipline + sweep).

---
*Phase: 00-unify-lifetime-and-publication-semantics*
*Completed: 2026-04-17*
