## Context
Module bodies currently execute in the module namespace scope, so `var` and `fn` definitions become module members. This prevents safely introducing an explicit `self` parameter for module init and makes it impossible to have true local bindings in a module body.

## Goals / Non-Goals
- Goals:
  - Make module bodies behave like function bodies with lexical locals.
  - Allow explicit `self` in module init without breaking module scope.
  - Preserve `/` as the explicit path to module namespace writes.
- Non-Goals:
  - Redesign of import/export syntax.
  - Changes to namespace/class body semantics unless explicitly called out later.

## Decisions
- Module bodies compile into an init function that executes with a fresh lexical scope.
- Module namespace is available via `self`; `/`-prefixed symbols write to that namespace.
- Bindings created without `/` (e.g., `var`, `fn`, `class`, `ns`) are local to module init and are not exported unless explicitly written to `/`.

## Risks / Trade-offs
- **Breaking change**: existing modules relying on implicit exports will need `/`.
- Some code patterns may need refactoring to preserve exports.

## Migration Plan
- Update module definitions to use `/` for exported bindings.
- Add tests that demonstrate local vs exported bindings.

## Open Questions
- Should namespace/class bodies adopt the same local-by-default semantics, or remain member-by-default?
