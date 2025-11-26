# OOP Inheritance: Super Calls (Design)

This document captures the planned semantics for invoking superclass methods and constructors in Gene. It aligns with the macro/function conventions where `!` denotes unevaluated arguments.

## Goals
- Allow calling a parent method or constructor from inside a subclass implementation.
- Support both eager and macro variants (`.m` vs `.m!`, `.ctor` vs `.ctor!`).
- Keep invocation syntax minimal and uniform with existing call forms.

## Target Syntax

```gene
(.fn m [a b]
  (super .m a b)      # eager parent method
)

(.fn m [a b]
  (super .m! a b)     # macro parent method (unevaluated args)
)

(.ctor! [a b]
  (super .ctor! a b)  # macro parent constructor
)
```

## Semantics
- **Receiver**: `super` is only valid inside a method or constructor. It resolves to a proxy that carries:
  - the current instance (or custom value), and
  - the parent class (nearest ancestor).
- **Method lookup**:
  - `(super .m ...)` resolves `m` on the parent class. Fails if missing.
  - `(super .m! ...)` resolves the macro-method variant. Fails if missing or if only eager exists.
- **Constructor lookup**:
  - `(super .ctor ...)` / `(super .ctor! ...)` resolve the parent ctor/ctor! respectively.
  - The current instance is passed as implicit first argument; parent constructor sets up parent state, not a new instance.
- **Argument evaluation**:
  - `.m` / `.ctor` use evaluated arguments.
  - `.m!` / `.ctor!` receive quoted arguments (consistent with macro rules).
- **Errors**:
  - Using `super` outside a method/ctor → compile-time error.
  - No parent class → runtime error (“No parent class for super”).
  - Missing method/constructor on parent → runtime error (“Superclass has no method m”).
  - Macro/eager mismatch → runtime error (e.g., calling `.m!` when only eager exists).

## VM Model (planned)
- Introduce a `VkSuperProxy` that stores `{instance, parentClass}` pushed by `IkSuper`.
- Method/ctor dispatch detects the proxy:
  - Use `parentClass` for lookup.
  - Pass `instance` as `self` to the resolved method.
  - For macro-methods, reuse existing macro call path (quoted args).
  - For constructors, reuse ctor dispatch but with the existing instance (no allocation) and honor ctor vs ctor!.
- `IkSuper` is only emitted within compiled class bodies; elsewhere, the compiler emits an error.

## Compiler Notes
- Track “in class method/ctor” during class body compilation to allow `super`.
- `super` call sites compile like normal method calls; VM adjusts dispatch based on the receiver kind (super proxy).

## Testing Plan
- Happy paths:
  - `(super .m a b)` calls parent eager method with evaluated args.
  - `(super .m! a b)` calls parent macro-method with quoted args.
  - `(super .ctor! a b)` calls parent macro ctor with quoted args and the same instance.
- Errors:
  - `super` outside methods/ctors.
  - Missing parent or missing method/ctor on parent.
  - Calling `.m!` when parent only defines eager `.m` (and vice versa).

This design keeps the `!` contract consistent, reuses existing macro vs eager dispatch machinery, and introduces a minimal `super` proxy to route calls to the parent class.
