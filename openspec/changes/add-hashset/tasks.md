## 1. Implementation

- [x] 1.1 Add `HashSet` as a concrete arbitrary-value membership collection and register it in the runtime/stdlib alongside existing collection classes.
- [x] 1.2 Implement `HashSet` hashing and lookup semantics by reusing `HashMap`-compatible hashing behavior and runtime `==` collision resolution.
- [x] 1.3 Add constructor support for `(new HashSet item1 item2 ...)` and ensure duplicate inserts collapse to one member.
- [x] 1.4 Add core `HashSet` methods: `has` with `.contains` as an alias, `add`, `delete`, `size`, `clear`, `to_array`, `union`, `intersect`, `diff`, and `subset?`.
- [x] 1.5 Make `HashSet` iterable in `for` loops and add `$` / `println` rendering via `(HashSet item1 item2 ...)`.
- [x] 1.6 Add integration coverage for scalar members, composite members, collision handling, duplicate inserts, iteration, set algebra, printing, and unhashable-member errors.
