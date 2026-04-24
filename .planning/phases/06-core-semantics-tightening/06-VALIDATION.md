# Phase 06 Validation Strategy

status: planned
phase: 06-core-semantics-tightening
requirements: [CORE-02, CORE-03, CORE-04, CORE-05]

## Validation Approach

Phase 06 is a semantic contract phase. Validation must prove that each public
claim is backed by runnable tests and that docs no longer contradict the
runtime.

## Acceptance Checks

Run these checks after execution:

```bash
rg -n "nil|void|missing|optional|failed lookup|failed return" spec/02-types.md spec/17-selectors.md tests/integration/test_core_semantics.nim
rg -n "Gene expression evaluation|properties|children|macro input|caller_eval" spec/03-expressions.md spec/05-functions.md tests/integration/test_macro.nim
rg -n "Tested stable subset|Known gaps|exhaustiveness|arity|ADT|Option" spec/12-patterns.md tests/integration/test_pattern_matching.nim tests/integration/test_case.nim
nim c -r tests/integration/test_core_semantics.nim
nim c -r tests/integration/test_selector.nim
nim c -r tests/integration/test_macro.nim
nim c -r tests/integration/test_pattern_matching.nim
nim c -r tests/integration/test_case.nim
git diff --check
```

If VM, compiler, matcher, or selector implementation files change, also run:

```bash
nimble testintegration
```

## Requirement Coverage

| Requirement | Validation |
|-------------|------------|
| CORE-02 | Specs and `test_core_semantics.nim` distinguish `nil` and `void`; selector tests cover maps, arrays, Gene values, objects/instances, missing lookup, strict access, defaults, and nil receivers. |
| CORE-03 | Expression and function specs explain Gene properties/children, normal calls, macro input shape, `$caller_eval`, and metadata; macro tests inspect `.type`, `.props`, and `.children`. |
| CORE-04 | Pattern spec names the tested stable subset and known gaps; pattern/case tests cover destructuring, branch failure, arity/rest behavior, and experimental ADT/Option posture. |
| CORE-05 | Every new semantic claim has a grep-visible spec string and at least one runnable Nim test command. |

## Runtime Test Decision

Focused integration tests are mandatory. Full `nimble testintegration` is
mandatory only if execution changes runtime/compiler/matcher/selector source
files; docs-only and test-only changes can stop at the focused commands above.
