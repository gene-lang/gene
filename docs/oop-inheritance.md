# OOP Inheritance: Super Calls (Design)

This document captures the planned semantics for invoking superclass methods and constructors in Gene. It aligns with the macro/function conventions where `!` denotes unevaluated arguments.

## Goals
- Allow calling a parent method or constructor from inside a subclass implementation.
- Support both eager and macro variants (`.m` vs `.m!`, `.ctor` vs `.ctor!`).
- Keep invocation syntax minimal and uniform with existing call forms.
- Avoid runtime allocation overhead for `super` dispatch.

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
- **Receiver**: `super` is only valid inside a method or constructor.
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

## VM Model (allocation-free)
- Introduce dedicated opcodes instead of a heap proxy:
  - `IkCallSuperMethod` / `IkCallSuperMethodMacro` (carry method key)
  - `IkCallSuperCtor` / `IkCallSuperCtorMacro` (constructor call intent)
- At dispatch time:
  - Derive `instance` from the current scope (`self` binding or ctor frame arg0).
  - Derive `parentClass` from `frame.current_method.class.parent` (or `frame.current_class.parent` during ctor).
  - Look up the target on `parentClass` method/ctor tables. Use existing macro vs eager call paths: macro variants run with quoted args, eager variants evaluate args first. Constructor calls reuse ctor dispatch but skip allocation and use the existing instance as arg0.
- No super proxy allocation; failure paths raise as described above.

## Compiler Notes
- Track “in class method/ctor” during class body compilation; emit a compile-time error if `super` appears elsewhere.
- Lower `(super .m …)`, `(super .m! …)`, `(super .ctor …)`, `(super .ctor! …)` into the dedicated super-call instructions with the member key baked in. The call shape stays identical to normal method calls at the surface.

## Testing Plan
- Happy paths:
  - `(super .m a b)` calls parent eager method with evaluated args.
  - `(super .m! a b)` calls parent macro-method with quoted args.
  - `(super .ctor! a b)` calls parent macro ctor with quoted args and the same instance.
- Errors:
  - `super` outside methods/ctors.
  - Missing parent or missing method/ctor on parent.
  - Calling `.m!` when parent only defines eager `.m` (and vice versa).

This design keeps the `!` contract consistent, reuses existing macro vs eager dispatch machinery, and routes calls directly to the parent class without per-call allocations.
