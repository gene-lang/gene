# Generics Design for Gene (Updated)

**Original:** `docs/proposals/implemented/generics-design.md` (2026-02-07)
**Updated:** 2026-04-07 — inheritance rules, current implementation status

## Current Implementation Status

**Implemented:**
- Generic function syntax: `(fn identity:T [x: T] -> T x)`
- Generic method syntax: `(method echo:T [x: T] -> T x)`
- `TdkVar` type variable descriptors in type system
- Type variable resolution during parsing

**Not enforced:**
- Type variables erase to `Any` at runtime (`TdkVar` → `RtAny`)
- No unification — `(fn f [a: T b: T])` doesn't verify both args are the same type
- No compile-time constraint checking beyond descriptor creation

**Not implemented:**
- Generic classes
- Type bounds / constraints
- Reified runtime generic instances
- Monomorphization / specialized code generation

## Design Principles

1. **Gradual first** — Untyped code always works. Generics are opt-in.
2. **Inference over annotation** — The checker infers types where possible.
3. **Gene-native syntax** — Colons for type params: `fn:T`, `class:T:U`
4. **Invariant generics** — No variance. Simplifies everything.
5. **Type params propagate through inheritance** — Never fixed in subclasses.

## Syntax

### Generic Functions (implemented)

```gene
(fn identity:T [x: T] -> T x)
(fn map:A:B [arr: (Array A) f: (Fn [A] B)] -> (Array B) ...)
(fn first:A [a: (Array A)] -> A (a .get 0))

# Call site — type params inferred
(identity 42)           # T=Int
(identity "hello")      # T=String
```

### Generic Methods (implemented)

```gene
(class Echo
  (method echo:T [x: T] -> T x))
```

### Generic Classes (not yet implemented)

```gene
(class Stack:T
  (field items: (Array T))

  (ctor [items...: T]
    (/items = items))

  (method push [val: T]
    (items .push val))

  (method pop [] -> (Option T)
    (if (items .empty?)
      None
    else
      (Some (items .pop)))))

(class Pair:A:B
  (field first: A)
  (field second: B))

# Instantiation — type params inferred from arguments
(var s (new Stack 1 2 3))     # T=Int
(var p (new Pair "age" 30))   # A=String, B=Int
```

## Inheritance Rules

### Core Rule: Child Must Have Same or More Type Params

When a class extends a generic parent, the child **must carry all of the parent's
type parameters** (in the same positions) and may add more. Type parameters cannot
be fixed/specialized in subclasses.

```gene
# Parent: 1 type param
(class Stack:T ...)

# OK — same number, T passes through
(class BoundedStack:T < Stack
  (field max_size: Int))

# OK — more params, T passes through, adds U
(class TaggedStack:T:U < Stack
  (field tag: U))

# NOT ALLOWED — fewer params (fixes T to Int)
# (class IntStack < (Stack Int))   # ERROR: must propagate T
```

### Rationale

1. **No type substitution needed.** Parent method signatures use `T` as-is in the
   child. No substitution map, no signature rewriting, no override checking against
   substituted types.

2. **Simpler `instanceof`.** `(x is Stack)` works for any `Stack:T` regardless of
   what `T` is. No need to match type arguments in the check.

3. **No variance question.** Since type params are always open, there's no question
   of whether `Stack:Int` is a subtype of `Stack:Any`. They're both just `Stack`
   with a type argument.

4. **Consistent with erasure.** Since Gene erases type vars to `Any` at runtime,
   fixing a type param in a subclass would create a false sense of safety —
   the runtime wouldn't enforce it anyway.

### Concrete Specialization Without Inheritance

If you want an "IntStack", use a factory function or type alias instead of inheritance:

```gene
# Factory function
(fn new_int_stack []
  (new (Stack Int)))

# Or just use Stack directly with type annotation
(var s: (Stack Int) (new Stack 1 2 3))
```

### Multiple Inheritance Levels

```gene
(class Container:T ...)
(class OrderedContainer:T < Container ...)         # same T
(class IndexedContainer:T:K < OrderedContainer ...) # adds K for key type
```

Type params accumulate — each level adds but never removes.

### Method Override

Child methods see the same type params as the parent. Overrides must match
the parent's signature exactly:

```gene
(class Stack:T
  (method push [val: T] ...))

(class BoundedStack:T < Stack
  # Override uses the same T — no substitution needed
  (method push [val: T]
    (if ((items .size) < max_size)
      (super .push val)
    else
      (Err "stack full"))))
```

## Variance

**Decision: Invariant.**

`Stack:Int` and `Stack:String` are unrelated at the type level. There is no
subtyping relationship between different instantiations of the same generic class.

```gene
(fn process [s: (Stack Any)]
  (s .push "hello"))

(var ints (new (Stack Int) 1 2 3))
# (process ints)   # Type error: Stack:Int is not Stack:Any
```

This prevents the classic unsoundness of covariant mutable containers. Since Gene
is dynamically typed, the runtime would catch actual type errors anyway, but
invariance provides better compile-time warnings.

## Runtime Behavior

### Type Erasure (current)

Type variables erase to `Any` at runtime. This means:

```gene
(var s (new Stack 1 2 3))
(s .push "hello")           # No runtime error — T is erased
(s .is Stack)               # true
# (s .is (Stack Int))       # Can't check — type args erased
```

### Future: Reified Generics

The original design doc called for reified generics (type args preserved at runtime).
This remains a future goal but is not needed for the initial implementation:

```gene
# Future — NOT YET IMPLEMENTED
(var s (new Stack 1 2 3))
(s .type_params)            # [Int]
(s .is (Stack Int))         # true
(s .is (Stack String))      # false
```

Reification requires storing type args in the instance and checking them at
boundaries. This is deferred until the type system matures.

## Type Bounds / Constraints (future)

```gene
# Future — NOT YET IMPLEMENTED
(fn sort:T [arr: (Array T)] -> (Array T)
  ^where [(T .responds_to "compare")]
  ...)
```

Deferred. Gene's duck typing means `.compare` just works or fails at runtime.
Bounds would improve error messages but aren't required for correctness.

## Implementation Phases

### Phase 1: Generic Functions (done)
- [x] `fn name:T` syntax parsing
- [x] `TdkVar` type variable descriptors
- [x] Type variable resolution in function parameter annotations
- [ ] Type variable unification at call sites
- [ ] Runtime type variable binding (first arg fixes T)

### Phase 2: Generic Classes
- [ ] `class Name:T` syntax in compiler
- [ ] Type params stored in class definition
- [ ] Inheritance rule: child >= parent type param count
- [ ] Method signatures carry parent's type vars
- [ ] `(new Stack 1 2 3)` infers T from constructor args

### Phase 3: Enforcement
- [ ] Compile-time: warn on obvious type mismatches
- [ ] Runtime: boundary checking at function/method call
- [ ] Type variable unification within a single call

### Phase 4: Reification
- [ ] Store type args in instances
- [ ] `(x .is (Stack Int))` runtime check
- [ ] `(x .type_params)` introspection

### Phase 5: Optimization
- [ ] Specialized native code for typed collections
- [ ] Unboxed storage for `(Array Int)`
- [ ] Monomorphization for hot paths

### Phase 6: Polish
- [ ] Type bounds / constraints
- [ ] Better error messages for generic type mismatches
- [ ] Method-level type parameters (separate from class-level)

## Files

- `src/gene/utils.nim` — `split_generic_definition_name()` parses `fn:T:U`
- `src/gene/types/type_defs.nim` — `TdkVar` descriptor
- `src/gene/types/core/functions.nim` — `ensure_local_generic_type_id()`, function parsing
- `src/gene/types/core/matchers.nim` — type resolution with `type_vars` table
- `src/gene/types/runtime_types.nim` — `TdkVar` → `RtAny` erasure
- `src/gene/vm/args.nim` — runtime type enforcement
- `testsuite/02-types/types/10_generic_and_guards.gene` — generic function tests
