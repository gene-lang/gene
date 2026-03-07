## Context

The current runtime already has enough method dispatch machinery to implement an iteration protocol without introducing new bytecode instructions in the first wave. That keeps the change smaller and avoids touching more VM hot paths than necessary.

## Goals / Non-Goals

- Goals:
  - Unify `for` iteration and selector iterable expansion on one runtime contract.
  - Preserve `NOT_FOUND` as the exhaustion sentinel.
  - Support arrays, maps, and generators first.
- Non-Goals:
  - Full lazy selector streams as first-class iterator values.
  - Range/string/gene iteration in this first implementation wave.
  - New bytecode instructions for iterators.

## Decisions

- Decision: use native methods `.iter`, `.next`, and `.next_pair`.
  - Arrays and maps return dedicated iterator instances.
  - Generators return themselves from `.iter`.
- Decision: refactor `for` lowering in the compiler instead of adding iterator opcodes.
  - This reuses existing method-call instructions and existing loop control flow.
- Decision: `for [k v] in value` uses `.next_pair`; plain `for x in value` uses `.next`.

## Risks / Trade-offs

- Iterator methods are native-only in v1. Selector iterable expansion will therefore rely on native method lookup rather than full generic method dispatch.
- Map iteration order remains whatever the current map storage provides.

## Migration Plan

1. Add iterator classes and generator iterator methods.
2. Switch `for` to `.iter` / `.next` / `.next_pair`.
3. Teach selectors `*` / `**` to consume iterables.
4. Add tests for arrays, maps, generators, and selectors.
