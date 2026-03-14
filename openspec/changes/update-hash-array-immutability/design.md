## Context

The parser currently routes `#[...]` through `read_stream`, producing `VkStream`. Arrays do not yet carry an immutability bit, so changing the syntax alone would not satisfy the proposal semantics.

## Goals / Non-Goals

- Goals:
  - Make `#[...]` produce an immutable array value.
  - Preserve normal array read behavior for immutable arrays.
  - Reject runtime mutations against immutable arrays with explicit errors.
- Non-Goals:
  - Define replacement literal syntax for streams.
  - Add immutable map/gene syntax in this change.
  - Optimize immutable arrays beyond what is needed for correctness.

## Decisions

- Decision: represent immutable arrays as normal array objects with an explicit `frozen` flag.
- Alternatives considered: introduce a new `ValueKind` for frozen arrays. Rejected because it would widen the change surface across equality, serialization, display, and dispatch.

- Decision: keep `VkStream` in the runtime, but remove `#[]` as its literal syntax.
- Alternatives considered: remove streams entirely in the same change. Rejected because stream support still exists in the runtime and replacement syntax is not yet chosen.

- Decision: enforce immutability at mutation boundaries (`.add`/`.append`, indexed assignment, and any other in-place array mutators).
- Alternatives considered: copy-on-write on mutation. Rejected because the proposal explicitly wants immutable value semantics rather than implicit mutation through aliases.

## Risks / Trade-offs

- Existing tests and any downstream code using `#[]` as a stream literal will break.
- Mutation coverage must be audited carefully; missing one mutation path would undermine the feature.

## Migration Plan

1. Land immutable-array syntax and runtime guards.
2. Update all in-repo `#[]` stream uses to another construction path or disable them temporarily.
3. Propose replacement stream literal syntax in a follow-up change.

## Open Questions

- Should immutable arrays print distinctly from mutable arrays?
- Do we want a runtime predicate such as `.immutable?` in the same change, or later?
