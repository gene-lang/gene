## Context
Gene is currently dynamically typed. AI-first goals require predictable, machine-checkable semantics, which means adding a static type system and a typed OOP model without rewriting the VM.

## Goals / Non-Goals
- Goals:
  - Gene-valid type expressions for generics and functions.
  - Type annotations for functions and classes.
  - A compile-time type-checking phase with clear errors.
  - Nominal class typing with typed field/method access.
- Non-Goals:
  - Effect system (tracked in later phases).
  - Runtime type enforcement in the VM.
  - Full HM-style global inference if it complicates migration.

## Decisions
- **Type expression syntax**: Use S-expression constructors (e.g., `(Array T)`, `(Result T E)`, `(Option T)`, `(Tuple A B ...)`).
- **Function type syntax**: Canonical form is `(Fn [^a A ^b B C D] R)`. The param list is ordered; `^name Type` pairs are optional labels for keyword-arg checking, while bare types remain positional.
- **Keyword arguments**: Keyword arguments are passed as a map at runtime. The type checker validates keyword keys against labeled params and their value types. Arguments not declared in the function type are rejected (no extra positional or keyword args unless a future variadic form is introduced).
- **Nominal class types**: A class name defines its instance type. Methods are typed as `(Fn [Self ...] R)`.
- **Field typing**: Require explicit declarations via a class property, e.g.:
  `(class Point ^fields {^x Int ^y Int} (ctor [x: Int y: Int] ...))`
  Property access `obj/.x` is validated against `^fields`.
- **Unknown types**: Use explicit `Any` to opt out; missing/inferable types should become errors in strict mode.
- **Default mode**: Type checking is on by default. Provide an opt-out flag for migration.

## Risks / Trade-offs
- **Breaking change risk**: Existing unannotated code will fail in strict mode.
- **Migration complexity**: Tooling needed to add annotations or opt into `Any`.
- **OOP ambiguity**: Inference from constructors is convenient but adds complexity.

## Migration Plan
- Provide an opt-in flag for type-checking initially (or a `gene check` command) if strict-by-default is too disruptive.
- Add a formatter or helper to insert `Any` where needed.

## Open Questions
- Do we need `Self` as a reserved type symbol, or should it be expanded at parse time?
