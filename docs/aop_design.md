# AOP (Aspect-Oriented Programming) Design for Gene

## Overview

Add lightweight AOP building blocks to Gene that integrate with existing function, macro, and method systems while maintaining **near-zero performance overhead**.

---

## Advice Types

| Advice | Description | Special Variables |
|--------|-------------|-------------------|
| `before` | Runs before target; can modify args | `$args` |
| `before_filter` | If returns falsy, target is skipped | `$args` |
| `after` | Runs after target; can modify result | `$args`, `$result` |
| `around` | Wraps target; controls execution | `$args`, `$call_target` |
| `invariant` | Runs before AND after | `$args`, `$result` (after phase) |

---

## Syntax Examples

```gene
# Basic function
(fn calculate [a b] (+ a b))

# before: modify args
(calculate = (before calculate
  (fnx [a b]
    ($args/0 = (* a 2)))))

# after: modify result  
(calculate = (after calculate
  (fnx [a b]
    ($result = (* $result 10)))))

# around: full control
(calculate = (around calculate
  (fnx [a b]
    (+ ($call_target) 100))))

# before_filter: conditional execution
(calculate = (before_filter calculate
  (fnx [a b]
    (> a 0))))

# invariant: Design by Contract
(calculate = (invariant calculate
  (fnx [a b]
    (assert (> a 0)))))

# Access original: calculate/$wrapped
```

---

## Execution Order

```
before_filters → befores → invariants(pre) → around/target → invariants(post) → afters
```

Multiple advices of same type execute in order of application.

---

## Performance Strategy

**Compile-time inlining**: When aspects are applied, generate a single CompilationUnit that inlines all advice code.

```
┌─────────────────────────────────────────────────────────┐
│              Compiled WrappedCallable                   │
├─────────────────────────────────────────────────────────┤
│ before_filters → befores → target → afters              │
│            (single CompilationUnit)                     │
└─────────────────────────────────────────────────────────┘
```

**No runtime dispatch** - advice is compiled directly into the callable's bytecode.

---

## Type Design

### WrappedCallable

```nim
WrappedCallable* = ref object
  wrapped*: Value               # Original callable
  before_advices*: seq[Value]   # Before advice functions
  before_filters*: seq[Value]   # Before filter functions
  after_advices*: seq[Value]    # After advice functions
  around_advice*: Value         # Around advice (one only)
  invariant_advices*: seq[Value]
  body_compiled*: CompilationUnit
  dirty*: bool                  # Needs recompile
```

### ValueKind

```nim
VkWrappedCallable  # New enum value
```

---

## Stdlib Builtins

| Builtin | Signature | Returns |
|---------|-----------|---------|
| `before` | `(before target advice)` | WrappedCallable |
| `after` | `(after target advice)` | WrappedCallable |
| `around` | `(around target advice)` | WrappedCallable |
| `before_filter` | `(before_filter target advice)` | WrappedCallable |
| `invariant` | `(invariant target advice)` | WrappedCallable |

Each builtin:
1. Creates WrappedCallable if target is Function/Method/Block
2. Or appends to existing WrappedCallable
3. Sets `dirty = true`
4. Returns the WrappedCallable

---

## VM Execution

When calling a WrappedCallable:
1. If `dirty`, recompile combined body
2. Execute the compiled unit

### Special Variable Handling

- `$args`: Set to args array at call entry
- `$result`: Set after target execution, modifiable in after/invariant
- `$call_target`: Closure that invokes wrapped callable
- `$wrapped`: Reference to original unwrapped callable

---

## Method AOP

```gene
# Direct method wrapping
(Calculator/.add = (before Calculator/.add advice))

# Or method-specific syntax
(before_method Calculator "add" advice)
```

---

## Multiple Aspects

Aspects compose by nesting/sequencing:

```gene
(f = (before f advice_1))
(f = (before f advice_2))  # Both run: advice_1 then advice_2

(f = (around f around_1))
(f = (around f around_2))  # around_2 wraps around_1 wraps f
```

---

## Implementation Files

| File | Purpose |
|------|---------|
| `types/type_defs.nim` | WrappedCallable type, VkWrappedCallable |
| `stdlib.nim` | before/after/around/before_filter/invariant |
| `vm.nim` | WrappedCallable execution |
| `compiler.nim` | AOP compilation support |

---

## Open Questions

1. **invariant phase detection**: Use `$phase` variable or separate before/after?
   - **Decision**: Single callback, `$result` is nil in before phase, set in after phase

2. **Compile timing**: Compile on first call or immediately?
   - **Decision**: Compile on first call (lazy) for efficiency

3. **Thread safety**: How to handle dirty recompilation in threads?
   - **Decision**: Each thread gets its own compiled copy
