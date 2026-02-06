## Context
Runtime type validation currently operates on simple type names and only validates annotated function arguments. The static type checker already infers richer types (unions, functions, applied types), but those results are not used at runtime.

## Goals / Non-Goals
- Goals:
  - Enforce inferred/annotated binding types at runtime for var/assignment.
  - Support union and function type compatibility in runtime checks.
  - Preserve runtime type metadata in GIR.
- Non-Goals:
  - Full runtime validation of generic parameter types (e.g., checking every Array element).
  - Changing the surface syntax of type annotations.

## Decisions
- Decision: Represent runtime-checked types as canonical type strings produced by the type checker.
- Decision: Store expected types per scope index on ScopeTracker so the VM can validate assignments by index.
- Decision: Extend argument annotation capture to keep full type expressions, and treat missing annotations as Any.

## Risks / Trade-offs
- Parsing type expressions at runtime adds overhead; limit parsing to validation paths only.
- Generic parameter enforcement is deferred to avoid per-element checks and performance regressions.

## Migration Plan
- Add type metadata fields and serialization first.
- Wire type checker inference into compiler metadata emission.
- Enable runtime validation and add tests.

## Open Questions
- Should runtime treat unannotated function parameters as Any or as incompatible with typed function types?
