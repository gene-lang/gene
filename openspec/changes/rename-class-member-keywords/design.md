## Context
Class members are currently declared with dotted symbols (`ctor`, `method`), which are visually similar to method calls and inconsistent with other declaration keywords. This change introduces explicit keywords to improve readability and reduce ambiguity.

## Goals / Non-Goals
- Goals:
  - Introduce `ctor`/`ctor!` for constructors and `method` for methods.
  - Keep `super` constructor calls in dotted form: `(super .ctor ...)` / `(super .ctor! ...)`.
  - Provide clear compile-time errors for legacy dotted forms.
- Non-Goals:
  - Preserve backward compatibility for `ctor`/`method`.
  - Change runtime method dispatch or constructor semantics beyond syntax.

## Decisions
- Decision: Replace dotted forms with keyword forms for class member declarations only.
  - Rationale: Clarifies declaration intent and aligns with keyword-style definitions elsewhere.
- Decision: Reject legacy dotted forms with explicit errors (no deprecation period).
  - Rationale: User requested immediate rejection and the change is intentionally breaking.
- Decision: Keep macro-like variants via `(ctor! [] ...)` and `(method m! [] ...)`.
  - Rationale: Preserve existing macro-like behavior while adopting new keywords.

## Risks / Trade-offs
- Breaking change for class member definitions; super constructor calls remain dotted but bare `ctor` is rejected.
  - Mitigation: Update all docs/examples/tests in the same change and emit targeted error messages.

## Migration Plan
1. Update compiler/parser to accept new keywords and reject legacy dotted forms.
2. Update all Gene sources, docs, and tests to the new syntax.
3. Run full test suite to validate.

## Open Questions
- None.
