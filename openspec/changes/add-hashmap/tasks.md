## 1. Implementation

- [ ] 1.1 Add `HashMap` as the concrete arbitrary-key `Any -> Any` map type and register it alongside the existing `Map`.
- [ ] 1.2 Implement `HashMap` hashing and lookup semantics, including built-in hash fast paths and `.hash` fallback for user-defined objects.
- [ ] 1.3 Add `{{ ... }}` parser/compiler support for alternating `HashMap` entries, treating adjacent `{{` as a literal opener while leaving ordinary nested `{` parsing unchanged.
- [ ] 1.4 Add core `HashMap` methods: `get`, `set`, `has` with `.contains` as an alias, `delete`, `size`, `clear`, `keys`, `values`, `pairs`, and `iter`.
- [ ] 1.5 Keep existing `Map` / `{}` / property-access behavior unchanged, keep `Map` independent from `HashMap`, and add `HashMap` string rendering via `{{ ... }}`.
- [ ] 1.6 Add integration coverage for scalar keys, composite keys, collision handling, literal parsing, whitespace/token distinction, iteration helpers, `.has`/`.contains`, printing round-trip, and unhashable-key errors.
