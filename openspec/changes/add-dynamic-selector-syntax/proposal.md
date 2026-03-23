## Why

Gene already has explicit dynamic selector and method-dispatch forms, but slash-path syntax only supports static segments. This makes common cases like "resolve one path segment from another path" verbose and inconsistent with the existing `a/x/y` shorthand.

The draft in `tmp/dynamic_selector.md` captures the desired direction, but the change needs a spec that stays aligned with current parser and compiler entry points. In particular, the language already has `(target ./ expr [default])` for dynamic lookup and `(obj . expr args...)` for dynamic method calls, so the new syntax should build on those forms rather than invent parallel operator semantics.

## What Changes

- Add `<>` dynamic segments inside slash-delimited selector/path syntax.
- Define `a/<path>` and `a/.<path>` as sugar for dynamic lookup and zero-argument dynamic method dispatch, with the inner `path` limited to slash-path fragments.
- Keep `(target ./ expr [default])` as the explicit form for arbitrary lookup expressions and `(obj . expr args...)` as the explicit form for argumentful dynamic method calls.
- Require dynamic method dispatch to support the same receiver kinds as static method calls, including value types such as strings and arrays.
- Add tests and docs for mixed static/dynamic paths, invalid dynamic selector results, and the `<>` grammar limits.

## Impact

- Affected specs: `selectors`
- Affected code:
  - `src/gene/compiler.nim`
  - `src/gene/compiler/operators.nim`
  - `src/gene/vm/exec.nim`
  - `src/gene/vm/dispatch.nim`
  - `tests/test_selector.nim`
  - `docs/proposals/future/selector_design.md`
- Related open changes:
  - `add-selector-transform`
  - `implement-complex-symbol-access`

