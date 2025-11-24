## 1. Definition
- [ ] 1.1 Lock remaining semantics (arity/type contract, return value) for argument matching and `match` expression; confirm scope reuse and shadowing.
- [ ] 1.2 Update `docs/pattern_matching_design.md` with the finalized scope, exclusions, and error model.

## 2. Spec
- [ ] 2.1 Add spec deltas describing argument matching and `match` expression semantics (scope reuse, no aggregate object, compile-time lowering).
- [ ] 2.2 Validate with `openspec validate add-pattern-matching-baseline --strict`.

## 3. Implementation (follow-on)
- [ ] 3.1 Update `compile_match` to use child access with scope/length checks per spec.
- [ ] 3.2 Add tests covering happy path and mismatch cases for arg matching and `match`.
