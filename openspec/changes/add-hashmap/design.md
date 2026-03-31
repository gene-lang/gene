## Context

Current Gene maps are backed by `MapObj` and keyed by interned `Key` symbols. That design is intentionally aligned with property access, namespace-like objects, and `{^name value}` literals. The requested `HashMap` serves a different need: a general-purpose keyed collection whose keys are arbitrary `Value`s rather than symbols.

Because `MapObj` stores `Table[Key, Value]`, `HashMap` cannot be modeled as a thin wrapper over the current map implementation without losing performance or key semantics. It needs a native runtime backing that understands arbitrary `Value` keys, hash bucketing, and runtime equality.

## Goals / Non-Goals

- Goals:
  - Add a Nim-backed `HashMap` runtime type for general-purpose `Any -> Any` keyed lookups.
  - Make `{{ key1 value1 ... }}` the user-facing construction surface for `HashMap`.
  - Use hash bucketing for performance while resolving collisions with runtime `==`.
  - Support primitive keys, structural composite keys, and user-defined objects that expose `.hash`.
  - Ship iteration helpers (`keys`, `values`, `pairs`, `iter`) in the first implementation.
  - Keep `Map` as the independent `Symbol -> Any` type used by `{}` and property-style access.
- Non-Goals:
  - Change `{}` or slash/property lookup to use `HashMap`.
  - Replace or deprecate the current symbol-keyed `Map`.
  - Define a wire format for `HashMap` serialization in this change.
  - Require users to construct `HashMap` through an explicit class name.

## Decisions

- Decision: make `HashMap` the concrete `Any -> Any` map type exposed by `{{ ... }}`.
  - Alternatives considered: using `BaseMap`. Rejected because "Base" reads as an abstract/internal parent, while the public collection here is concrete and user-facing.

- Decision: keep `HashMap` and `Map` as independent concrete types rather than a subtype hierarchy.
  - Alternatives considered: making `Map` inherit from `HashMap` or vice versa. Rejected because they have different backing stores, different key semantics, and no current need for inheritance-driven polymorphism.

- Decision: represent `HashMap` as a dedicated native runtime collection rather than reusing `MapObj`.
  - Alternatives considered: wrapping the current symbol-keyed map or encoding arbitrary keys into strings/symbols. Rejected because both approaches either lose semantics or introduce avoidable overhead and collision ambiguity.

- Decision: store `HashMap` entries in buckets keyed by a computed integer hash, with each bucket containing `(key, value)` pairs.
  - Alternatives considered: a flat linear sequence or a custom symbolization layer. Rejected because the requested use cases need near-map performance rather than linear scans.

- Decision: define key identity as "same computed hash" plus runtime `==`.
  - Alternatives considered: hash-only identity. Rejected because collisions must not alias unequal keys.

- Decision: compute hashes through a `HashMap`-specific helper that may fast-path built-ins but must be observationally equivalent to evaluating `.hash`.
  - Alternatives considered: method dispatch for every key, including hot-path scalars. Rejected because `HashMap` is explicitly performance-motivated; built-in fast paths should remain available.

- Decision: require hashes to be stable for keys while they are used in `HashMap`.
  - Alternatives considered: supporting rehash-on-mutation or live key tracking. Rejected because it adds substantial runtime complexity and is not needed for the initial collection API.

- Decision: expose `HashMap` via `{{ ... }}` literals plus explicit methods (`get`, `set`, `has`, `contains`, `delete`, `size`, `clear`, `keys`, `values`, `pairs`, `iter`) and not via property syntax.
  - Alternatives considered: adding selector/slash syntax for arbitrary keys. Rejected because it would blur the line between property maps and arbitrary-key data structures.

- Decision: make `.has` the canonical membership method and keep `.contains` as an alias.
  - Alternatives considered: treating both names as equally primary. Rejected because the surface is easier to document and test with one canonical name.

- Decision: include iteration helpers in the first implementation rather than deferring them.
  - Alternatives considered: shipping only point lookups/mutation initially. Rejected because `HashMap` would still be awkward for common collection use cases such as reverse indexes and cache inspection.

- Decision: reserve `{{ ... }}` as the `HashMap` literal while keeping `{ ... }` as the `Map` literal.
  - Alternatives considered: keeping `HashMap` constructor-only or overloading `{ ... }`. Rejected because the language needs a distinct literal surface that does not weaken the property-map role of `{}`.

- Decision: treat adjacent `{{` as a distinct literal opener, while whitespace-separated `{ {` continues to parse as ordinary nested tokens.
  - Alternatives considered: whitespace-insensitive brace merging. Rejected because nested map forms must remain unambiguous.

- Decision: render `HashMap` values using `{{ ... }}` so `$`/`println` round-trip semantically through the literal syntax.
  - Alternatives considered: generic object-style printing or `Map(...)` syntax. Rejected because the literal form is the clearest user-facing representation.

## Risks / Trade-offs

- Mutable composite keys can become unreachable if their hash-relevant contents change after insertion.
- If built-in structural hashes and runtime `==` ever diverge, lookup correctness will break; tests must lock that contract down.
- Adding a new native collection type widens the surface for printing, diagnostics, and future serdes support.

## Migration Plan

1. Add the `HashMap` proposal and approve the surface semantics.
2. Land the `HashMap` runtime representation, parser support, and class registration.
3. Add literal/method coverage and verify `Map` behavior remains unchanged.
4. Evaluate whether `HashMap` needs a follow-up proposal for serdes or shared interfaces with `Map`.

## Follow-Up

- Evaluate whether `HashMap` and `Map` should later share a common interface/protocol for generic map algorithms.
