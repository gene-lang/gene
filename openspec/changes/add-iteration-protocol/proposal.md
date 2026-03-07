## Why

Gene has generators and selector stream operators, but iteration is fragmented. `for` is still index-based, generators are not first-class iterables, and selectors `*` / `**` only expand materialized containers. A small shared iteration protocol unlocks these features without adding a second traversal model.

## What Changes

- Add a native iteration protocol based on `.iter`, `.next`, and `.next_pair`.
- Make arrays, maps, and generators iterable in the first implementation wave.
- Refactor `for` to use the iteration protocol instead of hard-coded index access.
- Extend selector `*` and `**` to consume iterables through the same protocol when direct container expansion is not available.

## Impact

- Affected specs: `iteration`
- Affected code:
  - `src/gene/compiler/control_flow.nim`
  - `src/gene/stdlib/collections.nim`
  - `src/gene/stdlib/selectors.nim`
  - `src/gene/vm/generator.nim`
  - tests in `tests/` and `testsuite/`
