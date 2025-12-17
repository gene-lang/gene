# Proposal: Add Selector Transform & Update Support

## Why

Selectors are intended to be Gene’s ergonomic layer for querying and transforming nested structures (maps, arrays, genes, namespaces, classes/instances). Today, selectors are primarily *read* primitives and don’t provide a coherent way to:

- Distinguish “missing” (`void`) from “present but empty” (`nil`) in a consistent way across selector access and selector objects.
- Update the *matched location(s)* rather than just returning the matched value.
- Express XSLT/CSS-like “select + apply rules” workflows (e.g. `examples/html2.gene`) where a selector identifies nodes and an action mutates those nodes.

Without an update/transform model, code devolves into manual tree walking and ad-hoc mutation logic.

## What Changes

### 1) Selector missing-value semantics
- Standardize selector reads so **missing ⇒ `void`** (not `nil`).
- Add `/!` (assert-not-void) so callers can opt into hard failure when missing.

### 2) Updatable selector matches (“locations”)
- Introduce a representation for “selector matches” that carries enough information to update:
  - container (parent)
  - key/index
  - value
  - optional match path metadata
- Add APIs to set/update/delete matched locations.

### 3) Rule-based transforms (CSS/XPath-inspired)
- Add a small rule layer that composes:
  - **selector** (match locations)
  - **action** (function / transformer)
- Enable `examples/html2.gene` style usage where rules can mutate a Gene AST (HTML tree) by selecting nodes and applying style updates.

## Impact

### Affected Code
- `src/gene/parser.nim`: literal tokens used in selector/rule DSL.
- `src/gene/compiler.nim`: selector/rule compilation and `/!` emission.
- `src/gene/vm.nim`: core selector lookup semantics and `/!` execution.
- `src/gene/stdlib.nim`: `Selector` APIs and new transform/update helpers.
- `docs/selector_design.md`: document the updated semantics and APIs.
- `examples/html2.gene`: becomes runnable once rule/transform pieces land.

### Risks
- **Behavior change**: returning `void` instead of `nil` for missing selector lookups impacts existing code paths.
- **Semantics creep**: CSS/XPath-like selectors are large; this change should be scoped into incremental milestones.

### Non-goals
- Full CSS selector / XPath axes, predicates, and performance optimizations in one shot.
- Persistent/immutable update semantics (this proposal focuses on in-place updates for mutable structures).

