## Context
Gene currently supports `fn`, `fnx`, and `fnxx` forms, and allows argument lists to be specified as a single symbol. This leads to multiple ways to write the same thing and increases the learning curve for app developers.

## Goals / Non-Goals
- Goals:
  - Single, consistent function definition syntax.
  - Bracketed argument lists required everywhere.
  - Clear migration path from legacy forms.
- Non-Goals:
  - Changing function semantics, closures, or invocation behavior.
  - Altering macro definitions beyond the `fnx!` removal.

## Decisions
- Decision: Keep `fn` as the only function definition form and require bracketed argument lists in all cases.
- Decision: Treat `fnx`, `fnx!`, and `fnxx` as ordinary symbols; compiler will reject them as function definitions.
- Alternatives considered: Keep `fnx` as a deprecated alias. Rejected to avoid long-term syntax ambiguity.

## Risks / Trade-offs
- Breaking change for existing code and tests.
- Short-term churn across docs and examples.

## Migration Plan
1. Replace `(fnx [args] ...)` with `(fn [args] ...)`.
2. Replace `(fnx name ...)` or `(fn name arg ...)` with `(fn name [arg] ...)`.
3. Update tools/docs/tests to use the new syntax.

## Open Questions
- Should we allow a deprecation period with warnings before hard errors?
