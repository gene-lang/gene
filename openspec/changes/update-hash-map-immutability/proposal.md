## Why

The value-vs-entity proposal reserves `#{...}` for immutable maps, but the implementation does not parse that syntax today. Maps are always mutable, and the runtime still uses `#{...}` as the display form for `VkSet`, which would conflict with immutable-map syntax.

## What Changes

- Add `#{...}` as immutable map literal syntax.
- Add immutable-map runtime semantics so map mutation attempts fail clearly instead of mutating in place.
- Add a map runtime predicate `.immutable?` so code can observe frozen state.
- **BREAKING** Stop using `#{...}` as the textual form for `VkSet` values so hash-brace syntax is unambiguous.
- Leave immutable gene syntax `#(...)` out of scope for this change.

## Impact

- Affected specs: `hash-literals`
- Affected code: `src/gene/parser.nim`, map constructors/types, map mutation paths in VM/stdlib, map/string rendering, GIR/serdes paths, parser/runtime tests
