## Why

`src/gene/stdlib.nim` is a 3,600+ line monolith that mixes unrelated responsibilities (core builtins, class wiring, strings, regex, JSON, collections, dates, selectors, AOP). This makes maintenance, review, and targeted changes unnecessarily risky.

## What Changes

- Split stdlib implementation into logical modules under `src/gene/stdlib/`:
  - `core.nim`
  - `classes.nim`
  - `strings.nim`
  - `regex.nim`
  - `json.nim`
  - `collections.nim`
  - `dates.nim`
  - `selectors.nim`
  - `gene_meta.nim`
  - `aspects.nim`
- Keep `src/gene/stdlib.nim` as a thin orchestrator that imports module files and coordinates initialization.
- Preserve behavior exactly (no feature changes, no semantics changes).

## Impact

- Affected specs: `stdlib-organization`
- Affected code:
  - `src/gene/stdlib.nim`
  - `src/gene/stdlib/core.nim`
  - `src/gene/stdlib/classes.nim`
  - `src/gene/stdlib/strings.nim`
  - `src/gene/stdlib/regex.nim`
  - `src/gene/stdlib/json.nim`
  - `src/gene/stdlib/collections.nim`
  - `src/gene/stdlib/dates.nim`
  - `src/gene/stdlib/selectors.nim`
  - `src/gene/stdlib/gene_meta.nim`
  - `src/gene/stdlib/aspects.nim`
