# Tail Call Optimization (TCO)

## Overview

Gene supports tail call optimization for self-recursive functions. When a function's last action is calling itself, the VM reuses the current frame instead of allocating a new one. This turns O(n) stack growth into O(1), enabling deep recursion without stack overflow.

## What gets optimized

A call is in **tail position** when its result is the direct return value of the enclosing function. The compiler tracks tail position through:

- Function body (the last expression)
- Sequence/`do` blocks (the last expression)
- `if`/`elif`/`else` branches (each branch body)

When a function call is in tail position, the compiler emits `IkTailCall` instead of `IkGeneEnd`. At runtime, `IkTailCall` detects same-function calls and reuses the frame.

## Examples

### Tail-recursive (optimized)

```gene
# Simple countdown - 100,000 deep, no stack overflow
(fn count_down [n]
  (if (n <= 0) "done"
  else (count_down (n - 1))))      # tail call

# Accumulator pattern
(fn sum [n acc]
  (if (n <= 0) acc
  else (sum (n - 1) (acc + n))))   # tail call

(sum 100000 0)  # => 5000050000

# Factorial with accumulator
(fn fact [n acc]
  (if (n <= 1) acc
  else (fact (n - 1) (n * acc))))  # tail call

(fact 20 1)  # => 2432902008176640000
```

### NOT tail-recursive (not optimized)

```gene
# Naive fibonacci - recursive calls are arguments to +, not in tail position
(fn fib [n]
  (if (n <= 1) n
  else ((fib (n - 1)) + (fib (n - 2)))))  # NOT tail calls

# Fix: rewrite with accumulator
(fn fib_acc [n a b]
  (if (n <= 0) a
  else (fib_acc (n - 1) b (a + b))))       # tail call

(fib_acc 50 0 1)  # fast, O(1) stack
```

## Scope

- **Self-recursion**: Optimized. The VM detects calls to the same function and reuses the frame.
- **Cross-function tail calls**: Not optimized. `(fn a [] (b))` where `b` is a different function still allocates a new frame. The `IkTailCall` handler falls back to regular call behavior in this case.
- **Method calls**: Not currently optimized. Only the `IkGeneEnd`/`IkTailCall` call path (general gene expression calls) participates. The `IkUnifiedCall*` fast paths do not emit `IkTailCall`.

## Implementation

The implementation has three parts:

1. **Compiler** (`src/gene/compiler/operators.nim`): When emitting a gene call in tail position, emits `IkTailCall` instead of `IkGeneEnd`.

2. **Tail position tracking** (`src/gene/compiler.nim`): The `tail_position` flag propagates through function bodies, sequences, and control flow branches. Non-tail contexts (loop bodies, array construction, non-last expressions) reset it to false.

3. **VM handler** (`src/gene/vm/exec.nim`, `IkTailCall`): For same-function calls, reuses the frame — updates args, resets scope, resets stack, jumps to PC 0. For different-function calls, falls back to regular call behavior.
