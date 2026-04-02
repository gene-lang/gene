## Why
Typed positional rest parameters currently require explicit array syntax such as `nums...: (Array Int)`. That is visually heavy for a common case and makes rest-parameter signatures less readable than fixed-parameter annotations. The more aesthetic spelling `nums...: Int` is sufficient for the intended meaning, and there is no meaningful existing usage that needs both forms.

## What Changes
- Make `rest...: T` the canonical typed positional rest syntax.
- Define `rest...: T` as element-type syntax that lowers to the internal bound-array form `rest...: (Array T)`.
- Treat any type expression consistently, so `rest...: (Array T)` means the bound rest value has internal type `(Array (Array T))`.
- Preserve current runtime binding and type metadata semantics so the bound rest variable still has array type.

## Impact
- Affected specs: `type-system`
- Affected code: `src/gene/type_checker.nim`, `src/gene/types/core/matchers.nim`, `tests/test_type_checker.nim`
