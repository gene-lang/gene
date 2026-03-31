## Why

Gene's existing `{}` maps are symbol-keyed and tuned for property-style access. They work well for namespace-like data, but they are not suitable for general-purpose keyed collections such as caches, reverse indexes, frequency tables, or lookup tables keyed by integers, strings, arrays, or domain objects.

## What Changes

- Add `HashMap` as the concrete arbitrary-key `Any -> Any` map runtime type backed by a native collection implementation.
- Add `{{ key1 value1 key2 value2 ... }}` literal syntax for `HashMap` with alternating key/value entries.
- Add core `HashMap` methods for data-structure use: `.get`, `.set`, `.has` (canonical), `.contains` (alias), `.delete`, `.size`, `.clear`, `.keys`, `.values`, `.pairs`, and `.iter`.
- Define `HashMap` key identity as `hash` plus runtime `==`: keys share a slot only when their hashes match and `==` reports equality.
- Define `$` / `println` rendering for `HashMap` using double-brace syntax so printed values round-trip semantically as `{{ ... }}`.
- Preserve current `{}` / `Map` semantics as the default `Symbol -> Any` property map and keep `Map` independent from `HashMap`.

## Impact

- Affected specs: `hash-map`
- Affected code: parser/collection literal handling, collection/runtime value types, stdlib class registration, hash/equality helpers, printing/diagnostics, and integration tests
