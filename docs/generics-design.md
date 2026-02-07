# Generics Design for Gene

**Author:** Sunni (AI) + Guoliang Cao  
**Date:** 2026-02-07  
**Status:** Draft / Discussion  

## Design Principles

1. **Gradual first** — Untyped code must always work. Generics are opt-in.
2. **Inference over annotation** — The checker should figure out types where possible. Users shouldn't need to write type variables in most code.
3. **Optimization hints** — Parameterized types like `(Array Int)` tell the compiler "this is homogeneous, optimize it." But `(Array)` or bare `Array` still works dynamically.
4. **Gene-native syntax** — No angle brackets, no special punctuation. Generics use the same S-expression + property syntax as everything else.
5. **OOP compatibility** — Generic classes use single inheritance normally. Type parameters don't break the class model.

## What Already Works

The type checker already has infrastructure for generics:

- `TkVar` — type variables (created by `fresh_var()`)
- `TkApplied` — parameterized types like `(Array Int)`, `(Result T E)`
- Unification — Hindley-Milner style, resolves type variables
- ADTs — `(type (Result T E) ((Ok T) | (Err E)))` works with pattern matching
- Union types — `(type UserId (Int | String))` works at runtime

## Scenario 1: Parameterized Collections

**Goal:** Express "this array contains only integers" for optimization and safety.

```gene
# Untyped — always works, no constraints
(var items [1 2 3])
(items .push "hello")  # Fine, it's dynamic

# Typed — optimization hint, checked at boundaries
(var nums: (Array Int) [1 2 3])
(nums .push 4)         # OK
(nums .push "hello")   # Type error at runtime

# Map with key/value types
(var scores: (Map String Int) {"alice" 95 "bob" 87})
```

**Question:** Should `(Array Int)` be enforced on every `.push` / `.set` call? Or only at function boundaries?

**Option A — Boundary only:** Check types when passing `nums` to a function that expects `(Array Int)`. Mutations aren't checked. Simpler, faster.

**Option B — Full enforcement:** Every mutation to a typed collection checks the element type. Safer, slower.

**Recommendation:** Option A for now. Boundary checking fits gradual typing philosophy. Full enforcement can be added later as a strict mode.

## Scenario 2: Generic Functions (Implicit)

**Goal:** Functions that work on any type, with the checker tracking what flows through.

```gene
# User writes this — no type variables needed
(fn first [arr: Array]
  (arr .get 0))

# Checker infers: (Fn [Array] Any)
# If called with (Array Int), checker knows result is Int

(var nums: (Array Int) [1 2 3])
(var x (first nums))
# Checker infers: x is Int (from Array Int → element type)
```

**Key insight:** Gene's dynamic nature means we don't need explicit `T`. The checker can track element types through applied types and infer return types from usage.

**Question:** Is fully implicit inference enough, or do we sometimes need explicit type params on functions?

## Scenario 3: Generic Functions (Explicit, if needed)

**Goal:** When inference isn't enough, allow explicit parameterization.

```gene
# Option A: Type params as part of function name/signature
(fn map ^T ^U [arr: (Array T) f: (Fn [T] U)] -> (Array U)
  ...)

# Option B: Type params in the param list with special syntax
(fn map [arr: (Array T) f: (Fn [T] U)] -> (Array U)
  ...)
# T and U are implicitly universally quantified (unknown = type variable)

# Option C: No explicit params, checker infers everything
(fn map [arr: Array f: Fn] -> Array
  ...)
# Checker figures out the relationship from the body
```

**Recommendation:** Option B — type variables appear naturally in annotations and the checker treats unknown type names as variables. No extra syntax needed. This is how the existing ADT definitions work: `(type (Result T E) ...)` uses T and E as parameters without special declaration.

## Scenario 4: Generic Classes

**Goal:** User-defined container types with type parameters.

```gene
# Parameterized class
(class (Stack T)
  (var items: (Array T) [])
  
  (method push [val: T]
    (items .push val))
  
  (method pop [] -> (Option T)
    (if (items .empty?)
      None
      (Some (items .pop)))))

# Usage
(var s (new (Stack Int)))
(s .push 42)
(s .push 7)
(var top (s .pop))  # (Option Int)
```

**Question:** Should `(class (Stack T) ...)` be the syntax, matching `(type (Result T E) ...)`?

**Question:** When creating instances, do we write `(new (Stack Int))` or `(new Stack ^T Int)` or something else?

**Recommendation:** `(class (Stack T) ...)` for definition, `(new (Stack Int))` for instantiation. Consistent with type syntax.

## Scenario 5: Type Aliases with Parameters

**Goal:** Named type aliases that accept parameters.

```gene
# Simple alias (already works via union types)
(type UserId (Int | String))

# Parameterized alias
(type (Pair A B) (Array))  # An array that holds exactly two items

# Alias with constraint
(type (NonEmpty T) (Array T))  # Semantically: must not be empty
```

**Question:** Are parameterized type aliases different from classes? Or should they just be sugar?

**Recommendation:** Keep type aliases lightweight — they're names for type expressions, not new runtime types. `(type (Pair A B) ...)` creates a compile-time alias. Classes create runtime types.

## Scenario 6: Constrained Types (Bounds)

**Goal:** Restrict what types can fill a parameter.

```gene
# Only types that have a .compare method
(fn sort [arr: (Array T)] -> (Array T)
  ^where [(T .responds_to "compare")]
  ...)

# Only numeric types
(fn sum [arr: (Array T)] -> T
  ^where [(T .is Numeric)]
  ...)
```

**Question:** Do we need type bounds/constraints? Or is runtime dispatch + duck typing sufficient?

**Recommendation:** Defer. Gene's dynamic nature means `.compare` just works or fails at runtime. Bounds are a "nice to have" for better error messages, not a necessity. Add them in a future phase if demand exists.

## Scenario 7: Variance (Covariance / Contravariance)

**Goal:** Should `(Array Dog)` be usable where `(Array Animal)` is expected?

```gene
(class Animal)
(class Dog < Animal)

(fn feed_all [animals: (Array Animal)]
  (for a animals (a .feed)))

(var dogs: (Array Dog) [(new Dog) (new Dog)])
(feed_all dogs)  # Should this work?
```

**Question:** Covariant (yes, Dog array is an Animal array) or invariant (no, they're different types)?

**Recommendation:** Covariant for read-only usage, invariant for mutation. But for MVP: just allow it (covariant) and document the caveat. Fits Gene's "flexible first" philosophy. The runtime will catch actual type errors at boundaries.

## Scenario 8: Interaction with Gradual Typing

**Goal:** Generics should degrade gracefully when types are missing.

```gene
# Fully typed
(fn identity [x: T] -> T x)

# Partially typed — T is inferred as Any
(fn identity [x] x)

# Mixed — works fine
(var nums: (Array Int) [1 2 3])
(var first_item (identity (nums .get 0)))
# Checker knows: first_item is Int (from Array Int)

# Untyped collection + typed function
(var items [1 "two" 3.0])
(var first_item (identity (items .get 0)))
# Checker knows: first_item is Any (from untyped Array)
```

**Key rule:** Missing type parameters default to `Any`. This preserves backward compatibility with all existing untyped code.

## Scenario 9: Generic Methods

**Goal:** Methods on classes that introduce their own type parameters.

```gene
(class Collection
  (var items [])
  
  # Method that works with any mapper function
  (method map [f: Fn] -> Collection
    (var result (new Collection))
    (for item items
      (result/.items .push (f item)))
    result))
```

**Question:** Do methods need their own type parameters, or is class-level + inference enough?

**Recommendation:** Inference handles most cases. The checker can track that if `f` is `(Fn [Int] String)`, then the result collection contains strings. Explicit method-level type params are low priority.

## Scenario 10: Native Code Optimization

**Goal:** Use type parameters to generate specialized native code.

```gene
# When the compiler sees (Array Int), it can:
# 1. Use unboxed int64 storage (no NaN-boxing overhead)
# 2. Generate SIMD operations for bulk math
# 3. Skip type checks on element access

(var nums: (Array Int) [1 2 3 4 5])
(var sum 0)
(for n nums (sum += n))
# With (Array Int): tight native loop, unboxed adds
# Without type: boxed values, NaN-tag checks per element
```

This is where generics pay for themselves in performance. The current native codegen pipeline (HIR → x86-64/ARM64) can use type parameter info to generate specialized code.

## Implementation Phases

### Phase 1: Applied Types (Mostly Done)
- [x] `TkApplied` in type checker
- [x] `(Array Int)`, `(Map String Int)` syntax parsed
- [x] ADTs with parameters: `(Result T E)`, `(Option T)`
- [ ] Runtime enforcement at function boundaries for applied collection types

### Phase 2: Inference Through Generics
- [ ] Track element types through collection operations (`.get`, `.push`, `.map`)
- [ ] Infer return types from applied input types
- [ ] Implicit type variables in function signatures (unknown names = type vars)

### Phase 3: Generic Classes
- [ ] `(class (Name T) ...)` syntax
- [ ] Type parameter substitution on instantiation
- [ ] Method signatures resolved with concrete type params

### Phase 4: Optimization
- [ ] Specialized native code for typed collections
- [ ] Unboxed storage for homogeneous arrays
- [ ] Monomorphization for hot paths (optional)

### Phase 5: Polish (if needed)
- [ ] Type bounds / constraints (`^where`)
- [ ] Variance rules
- [ ] Method-level type parameters
- [ ] Better error messages for generic type mismatches

## Open Questions

1. **Syntax for generic classes:** `(class (Stack T) ...)` — is this natural enough?
2. **Instantiation syntax:** `(new (Stack Int))` vs `(new Stack ^T Int)` vs inference?
3. **Boundary vs full enforcement:** Check element types on every mutation, or only at function call boundaries?
4. **Explicit type variables ever needed?** Or can inference + applied types cover all practical cases?
5. **Interaction with `.is`:** Should `((Array Int) .is Array)` return true? (subtype relationship)
6. **Erasure vs reification:** Do type parameters exist at runtime (reified) or only at compile time (erased)? Reified is more powerful but more complex.

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-07 | Lightweight generics (option 2) | Full generics too heavy for Gene's dynamic-first design |
| 2026-02-07 | Inference over annotation | Users shouldn't write type variables in most code |
| 2026-02-07 | Boundary enforcement for MVP | Simpler, fits gradual philosophy |
| | Syntax for generic classes | TBD |
| | Erasure vs reification | TBD |
