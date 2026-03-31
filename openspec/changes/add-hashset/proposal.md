## Why

Gene has `Map` for symbol-keyed property data and now `HashMap` for arbitrary key/value lookups, but it still lacks a native arbitrary-value set for membership tests, deduplication, and common set algebra. Users currently have to emulate sets with maps or arrays, which is awkward and slower than a dedicated runtime collection.

## What Changes

- Add `HashSet` as a concrete mutable set type for arbitrary `Value` members, constructed with `(new HashSet item1 item2 item3 ...)`.
- Add core `HashSet` methods for collection use: `.has` (canonical), `.contains` (alias), `.add`, `.delete`, `.size`, `.clear`, `.to_array`, `.union`, `.intersect`, `.diff`, and `.subset?`.
- Define `HashSet` member identity as computed hash plus runtime `==`, matching `HashMap` key semantics.
- Define `$` / `println` rendering for `HashSet` as `(HashSet item1 item2 item3 ...)` so printed values align with the constructor form.
- Make `HashSet` iterable in `for` loops without introducing a literal syntax in this change.

## Impact

- Affected specs: `hash-set`
- Affected code: runtime collection/value types, stdlib class registration, hash/equality helpers, iteration support, printing/diagnostics, and integration tests
