## Why

Gene should infer useful static types for `var` bindings without forcing annotations, so common code gets stronger safety by default while still allowing explicit dynamic opt-out with `Any`.

## What Changes

- Infer `var` binding types from initializer expressions when no annotation is provided.
- Extend inference coverage for `nil` and map literals to produce precise `TypeExpr` results.
- Keep explicit annotations authoritative (`Any` stays dynamic; concrete annotations remain enforced).
- Ensure assignment checks use inferred binding types.
- Keep function parameters without annotations defaulting to `Any`.
- Add language tests under `testsuite/types/` for inference behaviors.

## Impact

- Affected specs: `var-type-inference`
- Affected code:
  - `src/gene/type_checker.nim`
  - `testsuite/types/*.gene`
