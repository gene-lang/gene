# JIT: Arm64 Baseline Inline Plan

## Current State
- Baseline JIT exists for amd64/arm64 but emits helper calls (`jit_*`) for every opcode.
- Helper indirection prevents inlining; performance roughly matches interpreter.
- arm64 path is stable for fib but not faster; x64 path is unused here.

## Goals (arm64-first)
1) Inline the hot fib subset on arm64: stack push/pop/dup/swap, int add/sub, int comparisons, jumps, var resolve/subtract literal, unified call.
2) Operate directly on VM frame stack (`Frame.stack`/`stack_index`) and NaN-boxed small ints without helper calls.
3) Keep a slow-path to helpers when tags/overflow don’t match.
4) Prioritise arm64; x64 can be temporarily left unchanged or removed from baseline build if it blocks progress.

## Design Outline
- Extend `arm64/encoders.nim` with minimal instructions: LDR/STR (reg + imm), AND/OR/ADD/SUB (imm/reg), CMP/TST/CBZ/CBNZ, logical shift, and ADR-like materialisation for constants.
- Define JIT constants in Nim for codegen: `SMALL_INT_TAG`, `PAYLOAD_MASK`, `TRUE/FALSE/NIL`, and field offsets (`offsetof(VirtualMachine, frame)`, `offsetof(FrameObj, stack)`, `offsetof(FrameObj, stack_index)`).
- Arm64 codegen strategy (small-int fast path):
  - Maintain `vm` in `x0`, use callee-saved scratch (`x19+`) as needed.
  - PushValue: check stack_index bounds, store literal pointer into stack, increment stack_index.
  - Pop/Peek: decrement/index stack_index and load from stack; clear slot only if cheap.
  - Add/Sub: pop two, validate both are small ints (check tag), mask payload, add/sub, check overflow to stay in 48-bit, rebuild tagged int; slow-path branch to helper on failure.
  - Comparisons: similar tag checks, produce TRUE/FALSE constants.
  - Jump/JumpIfFalse: use CMP with TRUE/FALSE/NIL, branch via patched labels.
  - VarResolve/VarSubValue: compute scope pointer (respect parent depth) + slot offset, load, optionally subtract literal.
  - UnifiedCall: for fib, keep helper call for now; later inline a trampoline to interpreter/JIT.
- Fallback: branch to existing helper stubs on tag mismatch or overflow to preserve correctness.

## Task Breakdown
- T1: Add constants/offset helpers for VM/frame layout and tags in Nim (shared with baseline).
- T2: Extend `src/gene/jit/arm64/encoders.nim` with needed instruction emitters. ✅ (added ldr/str, ldrh/strh, add/sub, cmp, cbz/cbnz, and/orr, add with LSL for stack slots)
- T3: Teach `compile_function_arm64` to emit inline sequences for the small-int fast path (instructions listed above) with slow-path helper branches.
- T4: Keep amd64 path unchanged; disable it temporarily if it blocks compilation.
- T5: Bench + smoke-test (`benchmarks/scripts/benchme`, `nim c -r tests/test_basic.nim`); iterate on correctness/perf.

## Risks / Notes
- Offset/ABI drift: re-compute offsets from Nim (`offsetof`) to avoid hard-coding.
- NaN-boxing overflow: must bail out to helper on overflow or non-int payloads.
- Maintain `uses_vm_stack=true` semantics; avoid extra frame allocs.

## Current Status (2025-12-09)
- Safe helper-only baseline restored for arm64 (no inline fast path yet) to keep JIT stable.
- Bench: fib(24) correct; JIT slower than interpreter (0.060s vs 0.043s).
- Encoders and constants for inline work are in place; next step is to wire the small-int fast path in `compile_function_arm64` using the new emitters and tag checks, with slow-path helper fallback.
