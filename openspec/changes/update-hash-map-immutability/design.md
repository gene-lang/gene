## Context

Maps are implemented as `MapObj` values with in-place mutation across VM assignment paths and stdlib methods. The parser currently treats `{...}` as mutable maps and does not reserve `#{...}`. Separately, `VkSet` values render as `#{...}`, even though that syntax is not parser-backed, so introducing immutable maps requires disambiguating the hash-brace surface.

## Goals / Non-Goals

- Goals:
  - Make `#{...}` produce an immutable map value.
  - Preserve normal map read behavior for immutable maps.
  - Reject runtime mutations against immutable maps with explicit errors.
  - Remove `#{...}` as the display form for sets.
- Non-Goals:
  - Add immutable gene syntax `#(...)` in this change.
  - Add a first-class immutable set literal.
  - Redesign the set runtime beyond changing its display form if needed.

## Decisions

- Decision: represent immutable maps as normal `MapObj` values with an explicit `frozen` flag.
- Alternatives considered: introduce a separate `ValueKind` for frozen maps. Rejected because it would widen the change surface across lookup, equality, serialization, and dispatch.

- Decision: enforce immutability at map mutation boundaries, including `.set`, direct property assignment, and any in-place merge/delete helpers.
- Alternatives considered: copy-on-write mutation. Rejected because the proposal wants immutable value semantics, not implicit cloning through mutable APIs.

- Decision: expose frozen-state inspection via `Map.immutable?` in the same change.
- Alternatives considered: defer the predicate to a later proposal. Rejected because the surface is small and the user-facing proposal already relies on distinguishing value semantics explicitly.

- Decision: retire `#{...}` as the string form for `VkSet` and use an explicit unsupported marker for now.
- Alternatives considered: keep sets printing as `#{...}` and accept parser/display ambiguity. Rejected because literal roundtrips would become misleading once `#{...}` means immutable maps.

## Risks / Trade-offs

- Any latent code depending on `VkSet` pretty-printing as `#{...}` will change behavior.
- Mutation coverage must be audited carefully; missing one map mutation path would undermine immutable-map semantics.

## Migration Plan

1. Land immutable-map syntax and runtime guards.
2. Update in-repo tests/docs to treat `#{...}` as immutable maps.
3. Change `VkSet` display output to an explicit unsupported marker until set syntax is redesigned.
4. Propose immutable gene syntax separately.

## Follow-Up

- Long-term textual form for `VkSet` is deferred to a later set-syntax change.
