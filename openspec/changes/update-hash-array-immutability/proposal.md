## Why

`#[]` currently parses as a stream literal in the implementation and in the existing `hash-stream-parser` draft. That conflicts with the value-vs-entity proposal, which needs `#[]` to denote immutable arrays.

## What Changes

- **BREAKING** Change `#[...]` from stream literal syntax to immutable array literal syntax.
- Add immutable-array runtime semantics so mutation attempts fail clearly instead of silently mutating.
- Leave alternative stream literal syntax out of scope for this change; stream literal replacement will be proposed separately.
- Supersede the intent of the older `hash-stream-parser` draft.

## Impact

- Affected specs: `hash-literals`
- Affected code: `src/gene/parser.nim`, array constructors/types, array mutation paths in VM/stdlib, parser/runtime tests
