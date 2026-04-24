---
phase: 06-core-semantics-tightening
plan: 01
status: complete
completed_at: 2026-04-24
requirements_completed: [CORE-02, CORE-03, CORE-04, CORE-05]
commits:
  - 8d44ee9
  - f8b077e
  - fc84df5
  - 4b0d60e
---

# Phase 06 Plan 01 Summary

## Outcome

Completed Phase 06 core semantics tightening. Public specs and feature status
now distinguish `nil` from `void`, document selector lookup/default/strict
behavior, explain Gene expression evaluation and macro input shape, and bound
pattern matching to the tested subset.

## Changes

- Added `tests/integration/test_core_semantics.nim` and wired it into
  `nimble testintegration`.
- Specified `nil` as explicit data and `void` as a missing-result sentinel
  across maps, arrays, Gene values, instances, case no-match, and explicit nil
  function returns.
- Aligned selector docs/tests/source so defaults replace only `void`,
  first-class selector lookup on `nil` returns `nil`, stream modes drop
  `void`, and `$set` stays one segment.
- Documented ordinary Gene call evaluation, quoted Gene data shape, macro input
  shape, `$caller_eval`, and `$render`.
- Reframed pattern matching docs into tested stable subset, experimental
  subset, and known gaps; added nil-default destructuring coverage.
- Updated `docs/feature-status.md` and stable-core boundaries to remove Phase
  06 future-looking caveats.

## Verification

- `nim c -r tests/integration/test_core_semantics.nim`
- `nim c -r tests/integration/test_selector.nim`
- `nim c -r tests/integration/test_macro.nim`
- `nim c -r tests/integration/test_pattern_matching.nim`
- `nim c -r tests/integration/test_case.nim`
- `nim c -r tests/integration/test_stdlib_gene.nim`
- `git diff --check`
- `nimble testintegration`

## Remaining Risks

- Selector adapters still have older `member_or_nil` internals; Phase 06 did
  not broaden adapter semantics beyond the documented selector stable subset.
- Pattern matching remains experimental outside the documented tested subset.
- Advanced selector ranges, predicates, generator integration, and deep
  update/delete remain out of scope.
