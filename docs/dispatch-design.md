# Dynamic Dispatch Design

**Author:** Sunni (AI Assistant)  
**Date:** 2026-01-29  
**Status:** 🟢 Implementation

## Overview

Gene uses a two-phase dispatch system:
1. **Name resolution** - resolve function/method by name
2. **Type validation** - validate argument types match signature

This design supports gradual typing with NaN-tagged values.

## Dispatch Flow

```
Call site: (add x y)
    ↓
1. Resolve "add" by name
    ↓
2. Check argument types against signature
    ↓
3. Call if types match (or dynamic fallback)
```

## Type Representation

### Compile-Time
- Type annotations stored in TypeExpr (type_checker.nim)
- Generic type variables (TkVar) for parametric polymorphism
- Function types include parameter and return types

### Runtime
- NaN tagging provides fast type checks
- Type bits encoded in f64 value
- No separate type metadata needed for primitives
- Objects have type_id in header

## Generics

### Gradual Approach
```gene
# Type parameter T is for documentation/static checking
(fn [T] (identity [x ^T]) ^T
  x)

# At runtime: just use dynamic types from NaN tags
# No code specialization (like TypeScript)
# Type checking when annotations present
```

### Type Variable Resolution
- Type variables (^T) unified at compile-time when possible
- At runtime, treated as `Any` (accept any type)
- Future: JIT can specialize based on observed types

## Validation Strategy

### Single Validation (Not Overloading)
- One function per name (for now)
- Resolve name → get single candidate
- Validate args match or are compatible with `Any`

### Type Compatibility
```
Int     <: Any     (always)
Float   <: Any     (always)
T       <: Any     (type variables default to Any)
Any     -> Concrete (runtime check with NaN tag)
```

## Implementation Plan

### Phase 1: Enable Type Checking (Week 1)
- [ ] Make type_check=true by default in compiler
- [ ] Update CLI to support --no-type-check flag
- [ ] Make missing annotations default to ^Any
- [ ] Test with existing code

### Phase 2: Two-Phase Dispatch (Week 2)
- [ ] Add function signature storage in VM
- [ ] Implement name resolution phase
- [ ] Add argument type validation phase
- [ ] Runtime type checks using NaN tags

### Phase 3: Gradual Generics (Week 3)
- [ ] Ensure type variables default to Any at runtime
- [ ] No monomorphization (single code path)
- [ ] Allow generic functions to work with dynamic types

### Phase 4: Runtime Type Info (Week 4)
- [ ] Add type_id to object headers
- [ ] Implement `.is` type checks
- [ ] Support runtime type queries

## Example

```gene
# Function with type annotations
(fn (add [x ^Int y ^Int]) ^Int
  (+ x y))

# Call site
(add 1 2)   # OK: Int + Int -> Int
(add 1.0 2) # Error: Float incompatible with ^Int
```

### With Generics
```gene
# Generic identity function
(fn [T] (identity [x ^T]) ^T
  x)

# Calls
(identity 42)       # T = Int (inferred)
(identity "hello")  # T = String (inferred)
```

### Gradual Typing
```gene
# No annotations = Any
(fn (flexible [x y])
  (+ x y))

(flexible 1 2)       # OK: dynamic
(flexible "a" "b")   # OK: dynamic
```

## Notes

- Start simple: single validation per function name
- Gradual: missing annotations = Any
- NaN tagging gives us fast runtime type checks
- Future: overloading can be added later
- Future: JIT specialization based on type annotations
