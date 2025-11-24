## Context
We are finalizing the minimal pattern-matching story: argument matching (fast, no aggregate object) and a single-value `(match [pattern] value)` expression. Match must reuse the current scope and allow shadowing.

## Goals / Non-Goals
- Goals: document minimal semantics, preserve performance (no aggregate object for arg matching), define lowering strategy for `match`, capture open questions before implementation.
- Non-Goals: add full pattern language (maps, guards, or-patterns, view patterns), introduce pointer-based matcher/IkMatch optimization now.

## Decisions
- Scope: `match` reuses the current scope; shadowing is allowed.
- Input shape: `match` takes a single value operand; argument matching continues to consume stack args without aggregating.
- Lowering: keep compile-time destructuring (child access) for `match`; defer pointer-based matcher and IkMatch instruction.
- Performance: argument matching must not allocate an aggregate argument object.

## Open Questions
- Arity contract: what happens when pattern length ≠ value length (error vs. NIL padding vs. partial bind)?
A: arity mismatch is an error.
- Type contract: behavior when `value` is not an array/vector (error vs. treat as singleton vs. no-op); which sequence-like types are supported.
A: type mismatch is an error.
- Pattern forms: allowed primitives (identifier, wildcard, literal) and whether rest/splat is in-scope for this baseline.
A: identifier, wildcard, literal. No rest/splat.
- Result value: should `(match ...)` evaluate to `nil` or to a value (e.g., last binding) for this minimal version.
A: `nil`.
- Error model: exact exceptions/messages for arity/type mismatch and unsupported patterns.
A: meaningful error messages.
