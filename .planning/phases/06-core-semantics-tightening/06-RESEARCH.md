# Phase 06: Core Semantics Tightening - Research

**Researched:** 2026-04-24
**Domain:** nil/void semantics, selectors, Gene expression evaluation, macro input, pattern matching
**Confidence:** HIGH

## User Constraints

- Phase 06 follows Phase 05 and should use `docs/feature-status.md` as the
  stable-core boundary.
- Per user direction, planning was completed locally without Codex MCP.
- The user explicitly asked to ignore `__thread_error__`; that is outside this
  phase.

## Requirement Mapping

| ID | Requirement | Research Support |
|----|-------------|------------------|
| CORE-02 | User can distinguish `nil` from `void` across selectors, maps, arrays, objects, Gene properties, failed lookup, and function return behavior. | `spec/02-types.md` currently says no nil/void distinction, while selector specs/tests expose `void`; this needs a single contract. |
| CORE-03 | User can understand Gene expression properties, children, macro input, and metadata. | `spec/03-expressions.md` is too thin; `spec/05-functions.md` documents macros, and compiler code has distinct normal-call vs macro-call branches. |
| CORE-04 | User can identify stable pattern subset and known gaps. | `spec/12-patterns.md` already lists experimental areas, but the tested stable subset is not separated sharply. |
| CORE-05 | Semantic claims are backed by runnable tests or focused Nim tests. | Existing integration tests cover pieces; Phase 06 needs a focused core-semantics test file plus targeted selector/pattern additions. |

## Current Findings

### Nil And Void

- `docs/feature-status.md` marks values stable but says nil versus void needs
  Phase 06 tightening.
- `spec/02-types.md` lists `Nil` but not `Void` in primitive/value types and
  still says there is no distinction between explicitly nil and undefined/void.
- `src/gene/types/core/value_ops.nim` already renders both `nil` and `void`,
  so `void` is observable even if under-documented.
- `tests/integration/test_selector.nim` expects `{}/a` and `(./ {} "a")` to
  return `VOID`, while `nil/a` returns `NIL`.
- `tests/integration/test_case.nim` verifies `case` without `else` returns
  `NIL`, which is part of the function/control-flow return story.

Recommended contract:

- `nil` is an explicit value used for intentional absence and optional values.
- `void` is the absence of a requested member/index/match. It should not be the
  ordinary optional-value result.
- Missing map keys, missing Gene properties, missing instance properties, and
  out-of-range array/Gene child indices return `void`.
- Receivers that are `nil` propagate `nil` through ordinary lookup.
- Defaults replace `void` lookup failure, not explicit `nil`.
- Strict selector assertions reject both `void` and `nil`.
- Expressions with no successful branch, such as `case` without matching arm and
  no `else`, return `nil`.

### Selectors

- `spec/17-selectors.md` already says missing keys/indices return `void` and
  access on `nil` returns `nil`.
- `src/gene/vm/exec.nim` implements compiled slash lookup with that rule:
  `IkGetMemberOrNil` pushes `VOID` for `VOID` targets and `NIL` for `NIL`
  targets.
- `src/gene/stdlib/selectors.nim` has a likely mismatch for selector values:
  `apply_lookup` returns `VOID` when the base is `NIL`. That diverges from
  `nil/a` and the selector spec.
- `IkGetMemberDefault` currently returns the default for both `VOID` and `NIL`
  receivers. If the Phase 06 contract says defaults only replace missing
  `void`, this path needs a focused fix and tests.
- `$set` is intentionally one-segment only in `src/gene/compiler/misc.nim`.
  The docs should call that out as the stable update boundary.

Recommended approach:

1. Add tests that force compiled slash selectors and selector values to agree.
2. Fix only the mismatches exposed by those tests.
3. Document stream mode as dropping `void` matches and collecting empty arrays
   or maps when no stream values remain.
4. Document `$set` as one segment only; deep update/delete remains future work.

### Gene Expressions And Macros

- `spec/03-expressions.md` says everything is an expression but does not explain
  how a Gene expression splits into type/callee, properties, and children.
- `spec/05-functions.md` documents macro-like functions ending in `!` and
  `$caller_eval`, but does not show the exact AST shape DSL authors receive.
- `src/gene/compiler/operators.nim` has two branches:
  - normal calls compile/evaluate keyword properties and positional children
    before `IkUnifiedCall*`;
  - macro-like calls use a quoted branch so macro functions receive unevaluated
    Gene data.
- `tests/integration/test_macro.nim` proves macro arguments are not evaluated
  and `$caller_eval` uses caller scope, but it does not pin properties/children
  shape for macro input.
- `tests/integration/test_stdlib_gene.nim` proves Gene values expose `.type`,
  `.props`, and `.children`.

Recommended approach:

- Extend `spec/03-expressions.md` with a concrete Gene-expression evaluation
  section.
- Extend `spec/05-functions.md` with macro input shape examples using
  `.type`, `.props`, and `.children`.
- Add focused macro tests that inspect a macro argument containing both a
  property and children.

### Pattern Matching

- `tests/integration/test_pattern_matching.nim` covers simple destructuring,
  defaults, positional rest, Gene prop/child destructuring, prop rest, and some
  invalid rest/property cases.
- `tests/integration/test_case.nim` covers simple value `case/when` including
  unmatched case returning `nil`.
- `spec/12-patterns.md` mixes tested destructuring, case/when, ADT examples,
  Option examples, `?`, and known gaps without clearly separating the stable
  tested subset from experimental/future behavior.
- `src/gene/types/core/matchers.nim` intentionally uses `PLACEHOLDER` to
  distinguish no default from explicit `nil`; that is relevant to the nil/void
  contract.
- `src/gene/vm/args.nim` adapts Gene, array, and map inputs into matcher-style
  positional/keyword inputs for destructuring.

Recommended approach:

- Document the tested stable subset as destructuring plus simple value
  `case/when`.
- Keep ADT matching, Option matching, `?`, nested patterns, guards,
  exhaustiveness, map destructuring syntax, function-parameter patterns,
  or/as patterns, and broader arity diagnostics outside the stable subset unless
  this phase adds focused runnable coverage.
- Add tests for branch failure/no-match returning `nil`, invalid destructuring
  arity/rest behavior, and any ADT/Option claims left in the stable subset.

## Validation Architecture

Phase 06 validation should be a contract matrix: every semantic claim added to
the public specs must have either an existing runnable test cited in the plan or
a new focused Nim test added during execution.

Required validation commands:

```bash
nim c -r tests/integration/test_core_semantics.nim
nim c -r tests/integration/test_selector.nim
nim c -r tests/integration/test_macro.nim
nim c -r tests/integration/test_pattern_matching.nim
nim c -r tests/integration/test_case.nim
git diff --check
```

After execution, run `nimble testintegration` if Phase 06 changes VM,
compiler, matcher, or selector source files beyond docs/tests.

## Planning Recommendation

Use one execution plan with five tasks:

1. Publish nil/void value contracts and add focused core-semantics tests.
2. Tighten selector docs/tests and fix only confirmed selector mismatches.
3. Document Gene expression evaluation and macro input shape with tests.
4. Separate pattern-matching stable subset from known gaps and add tests.
5. Update `docs/feature-status.md`, run validation, and summarize the phase.
