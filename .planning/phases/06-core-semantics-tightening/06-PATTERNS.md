# Phase 06 Pattern Map

## Existing Patterns To Reuse

| Existing file | Pattern | Phase 06 use |
|---------------|---------|--------------|
| `tests/integration/test_selector.nim` | `test_vm` and `test_vm_error` assertions for runtime language snippets, with direct `Value` checks for `NIL` and `VOID`. | Extend for selector nil/void/default/stream/update edge contracts. |
| `tests/integration/test_macro.nim` | Macro-like `fn name!` tests proving unevaluated arguments and `$caller_eval`. | Add macro input shape tests for `.type`, `.props`, and `.children`. |
| `tests/integration/test_stdlib_gene.nim` | Reflection checks for Gene `.type`, `.props`, and `.children`. | Reuse the same assertions when documenting Gene expression data shape. |
| `tests/integration/test_pattern_matching.nim` | Focused destructuring coverage plus invalid-pattern `test_vm_error` checks. | Extend the tested stable subset and known error cases. |
| `tests/integration/test_case.nim` | Simple `case/when` value matching and no-match returning `NIL`. | Use as the branch-failure/exhaustiveness baseline for pattern docs. |
| `src/gene/vm/exec.nim` | `IkGetMemberOrNil`, `IkGetMemberDefault`, `IkAssertValue`, and selector-segment validation are the compiled slash selector runtime. | Fix only if tests prove default/nil behavior diverges from the Phase 06 contract. |
| `src/gene/stdlib/selectors.nim` | First-class selector value implementation with stream and entry modes. | Align selector value nil/default behavior with compiled slash selectors. |
| `src/gene/types/core/matchers.nim` and `src/gene/vm/args.nim` | Matcher parsing, default handling, splats, and destructuring input adaptation. | Read before changing pattern behavior; prefer tests/docs unless a real mismatch appears. |
| `gene.nimble` | `testintegration` enumerates integration test files explicitly. | Add any new `tests/integration/test_core_semantics.nim` file to the task. |

## Documentation Patterns

- `docs/feature-status.md` is the public stability hub. Update status rows
  after specs/tests are tightened; do not make claims only in planning files.
- `spec/17-selectors.md` is already structured by selector feature. Preserve
  that shape and add an explicit nil/void/default table.
- `spec/12-patterns.md` should separate "tested stable subset" from
  "experimental/future" instead of mixing both in examples.
- `spec/03-expressions.md` should own general expression evaluation rules.
  `spec/05-functions.md` should own macro/caller-eval details.

## Anti-Patterns To Avoid

- Do not broaden Phase 06 into a redesign of selectors, pattern matching, ADTs,
  or the type checker.
- Do not make `void` a normal optional-value replacement for `nil`.
- Do not silently change missing-member behavior without adding tests for maps,
  arrays, Gene values, instances, selector values, strict selectors, and
  defaults.
- Do not mark all pattern matching stable just because a subset is tested.
- Do not add dependencies or new test harness machinery.
