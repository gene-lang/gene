# Design: Selector Transform & Update Support

This design extends the existing selector machinery (`/`, `./`, `(@ ...)`, `VkSelector`) to support:

1) Consistent missing-value semantics (`void`), with opt-in strictness (`/!`)
2) Mutation of *matched locations* rather than just retrieving values
3) A minimal rule layer to support CSS-like application to Gene ASTs (HTML tree)

## 1) Values and missing semantics

### Missing vs empty
- **Missing**: return `void` (absent key/index/child/member).
- **Present but empty**: return `nil` if the stored value is `nil`.

### `/!` operator
`/!` asserts that the current value is not `void`.

- `a/b/!` throws if `a/b` is `void`.
- `a/!/b` throws if `a` is `void`, otherwise continues traversal.

Implementation: compile `/!` as a dedicated opcode (`IkAssertNotVoid`) and keep lookups returning `void` by default.

## 2) SelectorMatch (“location”) representation

Updating requires knowing where the match came from. A match location includes:

- `container`: parent object holding the matched value (map/array/gene/namespace/class/instance)
- `key`: for maps/props/members (symbol/string key)
- `index`: for arrays/gene children (int)
- `value`: current value at that location

Proposed runtime shape (Gene `Value`):
- `SelectorMatch` instance with props:
  - `container`, `key`, `index`, `value`

## 3) Core APIs

### Select
`selector/select(selector, target, ^mode :all|:first)` → array of `SelectorMatch`

Initial scope:
- Gene tree traversal (descendants) + type matching (for HTML): `_` and `:TAG` steps

### Update and mutation
- `selector/set(match, value)` → value
- `selector/update(match, fn)` → value
- `selector/delete(match)` → nil

User-facing helpers (thin wrappers):
- `$update target selector fn`
- `$transform target rules`

## 4) Minimal CSS prototype for `examples/html2.gene`

To support:

```gene
(var css (@*
  (@ _ :BODY (style ^line-height 1.5))
))
(css doc)
```

We need:

- A rule builder `@` (NOT the selector literal form) that accepts:
  - a selector expression (steps: `_`, `:BODY`, etc.)
  - an action (a transformer function)
- A rule-set combiner `@*` that returns a function applying all rules to a target.
- A `style` helper that returns a transformer function that sets/merges a gene’s `^style` map.

Because `(@ ...)` is already used as a selector literal today, the compiler should only treat `(@ ...)` as a selector literal when its arguments are selector path segments (string/symbol/int) and not a rule/action form.

## 5) Phasing

1) Lock down `void` + `/!` semantics for single-path selectors (already underway).
2) Introduce `SelectorMatch` and update APIs for direct path matches.
3) Add Gene-tree traversal + type filter steps to enable HTML rule application.
4) Expand toward CSS/XPath breadth (predicates, wildcards, sibling axes, etc.).

