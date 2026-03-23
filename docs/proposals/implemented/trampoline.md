# Trampoline: Calling VM Functions from Native Code

## Problem

Currently native-compiled functions can only call themselves recursively. Any function that calls another function (even a simple helper) is rejected by `isNativeEligible`. This severely limits which functions can be natively compiled.

We need a mechanism for native code to call back into the VM to invoke arbitrary callables: Gene functions, native (Nim) functions, methods, and bound methods.

## Design Goals

1. **Uniform interface** - one calling convention for all callable types
2. **Minimal overhead** - avoid unnecessary copies; box/unbox only at the boundary
3. **Type-safe** - use compile-time type info to select correct box/unbox paths
4. **Extensible** - support function calls now, method dispatch later

## Architecture Overview

```
Native JIT code                Trampoline (Nim, cdecl)                 VM
───────────────                ───────────────────────                 ──
                               ┌──────────────────────┐
set up args as int64     →     │ box int64 → Value    │          ┌──────────┐
load CallDescriptor ptr  →     │ dispatch on callable │    →     │ VM exec  │
call trampoline          →     │   VkFunction         │    →     │ or       │
                               │   VkNativeFn         │    →     │ native   │
receive int64 result     ←     │ unbox Value → int64  │    ←     │ dispatch │
                               └──────────────────────┘          └──────────┘
```

The key insight: native code always works with **int64 values** (the uniform ABI). The trampoline is the single point that translates between the native int64 world and the VM's boxed Value world.

**Invariant**: Gene's `Value` is a 64-bit NaN-boxed type (`uint64` under the hood). The entire trampoline design relies on `sizeof(Value) == 8`. If `Value` ever grows (e.g., 128-bit tagged pointer), the uniform int64 ABI, `CrtValue` path, and all `cast[int64](Value)` operations must be revised.

## Core Data Structures

### CallDescriptor

A compile-time-constructed descriptor stored alongside the native code. De-duplicated by (callable, argTypes, returnType) — multiple call sites targeting the same function with the same signature share one descriptor.

```nim
type
  CallArgType* = enum
    CatInt64    # arg is a raw int64
    CatFloat64  # arg is a float64 bitcast as int64

  CallReturnType* = enum
    CrtInt64    # result is int64, box as VkInt
    CrtFloat64  # result is float64 bitcast as int64, box as VkFloat
    CrtValue    # result is a raw Value bitcast as int64 (for untyped returns)

  CallDescriptor* = object
    callable*: Value              # The target: VkFunction, VkNativeFn, VkBoundMethod, etc.
    argTypes*: seq[CallArgType]   # Per-argument type info for boxing
    returnType*: CallReturnType   # How to interpret the int64 result
```

Descriptors are stored in a flat array on the Function. Call sites reference a descriptor by index into this array.

**Type safety**: If the callee has no type annotations, the function is **not eligible** for native compilation. We reject in `isNativeEligible` rather than guessing types. This avoids silent misboxing of floats/objects as integers. This applies uniformly to all callable types:
- **VkFunction**: type info comes from `matcher.has_type_annotations` and `matcher.return_type_name`
- **VkNativeFn**: type info must be registered explicitly (e.g., via a `native_type_sig` table mapping NativeFn pointers to their arg/return types). If a NativeFn lacks a registered signature, it is not eligible as a trampoline target.
- **VkBoundMethod**: type info comes from the underlying method's Function object

**Lifetime**: The `descriptors` seq is owned by the `Function` object (stored alongside `native_entry`). Since the Function outlives any native call into it, the descriptors remain valid.

Gene's `Value` is an untraced 64-bit scalar (NaN-boxed). It does not participate in Nim's GC. However, Values that represent ref types (VkFunction, VkNativeFn, etc.) encode a pointer to a heap-allocated `Ref` object. Gene uses manual ref-counting for these (`Ref` has a `rc` field). Storing a `callable: Value` in the descriptor does **not** automatically increment the ref count. When building descriptors, the implementation must explicitly call `incRef` on any ref-typed callable to prevent the target from being freed while the descriptor is alive. The matching `decRef` happens when the Function (and its descriptors) is freed.

### NativeContext

Runtime context passed into native code as a hidden parameter.

```nim
type
  NativeContext* = object
    vm*: ptr VirtualMachine
    trampoline*: pointer                              # address of native_trampoline proc
    descriptors*: ptr UncheckedArray[CallDescriptor]   # indexed by call site ID
    descriptor_count*: int32
```

Field layout (offsets used by codegen):
- `[ctx + 0]`  → `vm`
- `[ctx + 8]`  → `trampoline`
- `[ctx + 16]` → `descriptors`
- `[ctx + 24]` → `descriptor_count`

The codegen must use compile-time `offsetof` constants with static asserts rather than hard-coded numeric offsets:

```nim
const
  NativeCtxOffsetVm* = int32(offsetof(NativeContext, vm))
  NativeCtxOffsetTrampoline* = int32(offsetof(NativeContext, trampoline))
  NativeCtxOffsetDescriptors* = int32(offsetof(NativeContext, descriptors))

static:
  assert NativeCtxOffsetVm == 0
  assert NativeCtxOffsetTrampoline == 8
  assert NativeCtxOffsetDescriptors == 16
```

## Trampoline Function

A single C-callable entry point that handles all callable types:

```nim
proc native_trampoline*(
    ctx: ptr NativeContext,
    descriptor_idx: int64,
    args: ptr UncheckedArray[int64],
    argc: int64
): int64 {.cdecl, exportc.} =
  let idx = int(descriptor_idx)
  assert idx >= 0, "negative descriptor index"
  # Upper bound check is a debug guard; codegen should only emit valid indices.
  assert idx < int(ctx.descriptor_count), "descriptor index out of range"
  let desc = ctx.descriptors[idx]
  let n = int(argc)
  assert n == desc.argTypes.len, "argc/descriptor mismatch"

  # 1. Box arguments using a stack-allocated scratch buffer (max 8 args)
  #    This avoids heap allocation on every trampoline call.
  const MAX_NATIVE_ARGS = 8
  assert n <= MAX_NATIVE_ARGS
  var scratch: array[MAX_NATIVE_ARGS, Value]
  for i in 0..<n:
    case desc.argTypes[i]
    of CatInt64:
      scratch[i] = args[i].to_value()
    of CatFloat64:
      # Bitcast (not numeric conversion): reinterpret the int64 bits as float64
      scratch[i] = cast[float64](args[i]).to_value()
  # Wrap in a seq view for the VM dispatch (toOpenArray avoids copy)
  var boxed = scratch[0..<n]

  # 2. Dispatch based on callable type
  let result_val = case desc.callable.kind
    of VkFunction:
      ctx.vm.exec_function(desc.callable, @boxed)
    of VkNativeFn:
      call_native_fn(desc.callable.ref.native_fn, ctx.vm, @boxed)
    of VkBoundMethod:
      let bm = desc.callable.ref.bound_method
      ctx.vm.exec_method(bm.method.callable, bm.self, @boxed)
    else:
      ctx.vm.call_callable(desc.callable, @boxed)

  # 3. Unbox result
  case desc.returnType
  of CrtInt64:
    return result_val.to_int()
  of CrtFloat64:
    # Bitcast: reinterpret the float64 bits as int64 (matches uniform ABI)
    return cast[int64](result_val.to_float())
  of CrtValue:
    return cast[int64](result_val)
```

The trampoline is **one Nim proc** that never changes. All the variation is in the `CallDescriptor`. The stack-allocated scratch buffer avoids heap allocation per call; the `@boxed` conversion to seq is needed by the VM dispatch API but could be eliminated if those APIs accept `openArray` in the future.

`MAX_NATIVE_ARGS = 8` is the absolute hardware maximum (ARM64 has 8 integer registers). The per-architecture limits after reserving the context register are 5 (x86-64) and 7 (ARM64), enforced by `isNativeEligible`. The trampoline itself uses a pointer to an args array (not register-passed args), so 8 is safe as a buffer size — but no function will ever be compiled with more args than the arch limit allows.

## How Native Code Invokes the Trampoline

### Hidden Context Parameter

The VM pointer and descriptor table are passed into native code via a hidden first parameter. The native prologue stores it in a callee-saved register (or a dedicated stack slot) so it survives across calls.

On x86-64, use `r12` (callee-saved):
```asm
; Prologue addition: save context pointer
mov  r12, rdi          ; ctx is first arg (shifted: real args start at rsi)
```

On ARM64, use `x19` (callee-saved):
```asm
; Prologue addition: save context pointer
mov  x19, x0           ; ctx is first arg (real args start at x1)
```

This means the parameter registers shift by one: arg0 is now in `rsi`/`x1` instead of `rdi`/`x0`. The uniform int64 ABI is preserved; only the register assignment changes.

**Arg count limits**: The hidden context parameter consumes one register, reducing the register-passed arg limit to 5 (x86-64) or 7 (ARM64). Functions exceeding this are rejected by `isNativeEligible` — no stack-passed arguments are supported. This matches the existing limit enforcement and avoids complex stack ABI handling.

### Call Sequence (x86-64)

For a call site `result = other_fn(a, b)`:

```asm
; Spill any live values to stack (caller-saved)
; ...

; Set up trampoline args:
;   rdi = ctx pointer (from r12)
;   rsi = descriptor index (immediate)
;   rdx = pointer to args array on stack
;   rcx = arg count

mov  rdi, r12                   ; ctx
mov  rsi, <descriptor_idx>      ; which call site
lea  rdx, [rbp - <args_offset>] ; pointer to args (already on stack as int64)
mov  rcx, 2                     ; argc

; Load trampoline address from ctx
mov  rax, [r12 + 8]             ; ctx.trampoline (offset 8)
call rax                        ; indirect call

; Result is in rax (int64, possibly bitcast float)
mov  [rbp - <result_offset>], rax
```

### Call Sequence (ARM64)

```asm
mov  x0, x19                    ; ctx
mov  x1, <descriptor_idx>       ; which call site
add  x2, sp, <args_offset>      ; pointer to args on stack
mov  x3, 2                      ; argc

ldr  x8, [x19, #8]              ; ctx.trampoline (offset 8)
blr  x8                         ; indirect call

str  x0, [sp, <result_offset>]  ; store result
```

## HIR Changes

### New Op: HokCallVM

```nim
HokCallVM:
  dest: HirReg               # where to store the int64 result
  vmCallDescIdx: int32       # index into the descriptor table
  vmCallArgs: seq[HirReg]    # HIR registers holding the int64 args
```

This replaces `HokCall` for non-self calls. Self-recursive calls remain as `HokCall` (direct jump, no trampoline overhead).

### New Op: HokCallMethodVM (future)

```nim
HokCallMethodVM:
  dest: HirReg
  vmCallDescIdx: int32
  vmCallReceiver: HirReg     # the receiver object (as boxed Value in int64)
  vmCallArgs: seq[HirReg]
```

## Pipeline Changes

### bytecode_to_hir.nim

When converting `IkResolveSymbol` + `IkUnifiedCallN`:

1. If the symbol resolves to the function itself → emit `HokCall` (direct recursive call, existing path)
2. Otherwise → look up the symbol in the compilation scope, construct a `CallDescriptor`, emit `HokCallVM` with the descriptor index

The descriptor is built from:
- The resolved Value (function, native fn, etc.)
- The callee's type annotations to determine arg/return types

**Both caller and callee must have type annotations** for a trampoline call to be emitted. If the callee lacks type info, the call target is unresolvable for native purposes and `isNativeEligible` rejects the caller. This prevents silent misboxing.

### isNativeEligible

Relax the "only self-recursive calls" restriction. A function is eligible if:
- All its parameters have supported types (Int, Float)
- All instructions are in the supported set (expanded to include non-self calls)
- All call targets are resolvable at compile time (no dynamic dispatch on computed values)

### Codegen (x86_64_codegen.nim, arm64_codegen.nim)

- `genPrologue`: accept and store the hidden context parameter
- `genCallVM`: emit the trampoline call sequence (set up args array, load trampoline address, indirect call)
- `genCall` (self-recursive): adjust register assignments (args shift by one due to hidden ctx param)

## VM-Side Changes

### NativeContext Lifecycle

```nim
# In try_native_call, before invoking native code:
var ctx = NativeContext(
  vm: self,
  descriptors: compiled.descriptors,  # from NativeCompileResult
  trampoline: native_trampoline       # proc pointer
)

# Call with ctx as first arg:
result_i64 = cast[NativeFn_WithCtx](f.native_entry)(addr ctx, arg0, arg1, ...)
```

### NativeCompileResult Extension

```nim
NativeCompileResult* = object
  ok*: bool
  entry*: pointer
  code*: seq[byte]
  message*: string
  returnFloat*: bool
  descriptors*: seq[CallDescriptor]  # new: one per HokCallVM site
```

The `descriptors` seq is moved to the `Function` object on successful compilation (alongside `native_entry` and `native_ready`). The `NativeContext` constructed per-call points into the Function's descriptor storage, which is stable for the Function's lifetime. Since native code is only invoked through `try_native_call` which holds a reference to the Function, the descriptors cannot be freed mid-call.

## Example: Before and After

### Gene Source

```gene
(fn square [x: Int] -> Int
  (x * x))

(fn sum_of_squares [a: Int b: Int] -> Int
  ((square a) + (square b)))
```

### Today

`sum_of_squares` is **not** natively compiled because it calls `square` (a non-self function).

### With Trampoline

Both functions compile natively. `square` compiles as a pure native function (no VM calls). `sum_of_squares` compiles with two `HokCallVM` ops that invoke `square` through the trampoline.

If `square` is itself native-eligible, a future optimization could detect this and emit a direct native→native call instead of going through the trampoline. But the trampoline path is correct for all cases and is the right first step.

### HIR for sum_of_squares

```
function @sum_of_squares(%0: i64, %1: i64) -> i64 {
entry:
    %2 = callvm @0(%0) : i64    # descriptor 0 = square, argTypes=[CatInt64], ret=CrtInt64
    %3 = callvm @0(%1) : i64    # reuses descriptor 0 (same callable + same signature)
    %4 = add.i64 %2, %3
    ret %4
}
```

Descriptors are **de-duplicated by (callable, argTypes, returnType)**. Multiple call sites targeting the same function with the same signature share one descriptor. The `@N` index refers to the descriptor table, not the call site.

## Performance Considerations

**Cost per trampoline call:**
- ~5 instructions to set up the call (load ctx, descriptor idx, args ptr, argc)
- 1 indirect call
- Boxing: ~1-2 ns per argument (branch + store)
- VM dispatch: variable (function call overhead)
- Unboxing: ~1-2 ns for result

**Compared to pure native call:** ~20-50ns overhead for the trampoline + boxing round-trip. This is significant for tight loops but acceptable for less frequent calls. The important thing is that it **unblocks** native compilation for a much larger set of functions.

**Allocation**: The trampoline uses a stack-allocated `array[8, Value]` scratch buffer for boxing (see implementation above). The `@boxed` seq conversion for VM dispatch is a single allocation; this can be eliminated if `exec_function` and `call_native_fn` are updated to accept `openArray[Value]`.

**Future optimization path:**
1. **Direct native→native calls**: if the callee is also natively compiled, skip the trampoline entirely and call its native entry point directly (with appropriate ABI handling)
2. **Inline caching**: cache the callee's native entry at the call site for polymorphic dispatch
3. **Speculative inlining**: inline the callee's HIR at the call site

## Method Dispatch (Future Extension)

Method calls require knowing the receiver's class at call time. Two approaches:

### Approach A: Resolve at JIT Time (Monomorphic)

If the receiver type is known statically (e.g., from type annotations), resolve the method during HIR construction and store the resolved callable in the `CallDescriptor`. This makes method calls identical to function calls through the trampoline.

```gene
(fn distance [p: Point] -> Float
  (sqrt ((p .x * p .x) + (p .y * p .y))))
```

Here `p .x` and `p .y` resolve to known methods on `Point`, and the descriptor stores the resolved method Value.

### Approach B: Dispatch in Trampoline (Polymorphic)

For cases where the receiver type isn't known, add a `CallMethodDescriptor` variant:

```nim
CallMethodDescriptor* = object
  methodKey*: Value           # method name as symbol
  argTypes*: seq[CallArgType]
  returnType*: CallReturnType
```

The trampoline receives the receiver as the first argument, looks up the method via the class method table, and dispatches. This is slower but handles polymorphism.

### Receiver Boxing

The receiver (an object instance) is a boxed Value in the VM. In native code, it would be stored as a raw pointer (cast to int64). The trampoline casts it back to Value for dispatch. This means native code can hold references to VM objects but cannot manipulate their fields directly — field access also goes through the trampoline.

## Implementation Order

1. **Phase 1**: Function calls through trampoline (Gene functions + native functions)
   - Add `NativeContext`, `CallDescriptor`, trampoline proc
   - Add `HokCallVM` to HIR
   - Update bytecode_to_hir to emit `HokCallVM` for non-self calls
   - Update codegen for hidden context parameter and `genCallVM`
   - Relax `isNativeEligible`
   - Update `try_native_call` to construct and pass `NativeContext`

2. **Phase 2**: Direct native→native calls (optimization)
   - When the callee is also natively compiled, emit a direct call to its entry point
   - Skip boxing/unboxing entirely for native→native paths

3. **Phase 3**: Method dispatch through trampoline
   - Add `HokCallMethodVM`
   - Handle receiver boxing/unboxing
   - Support monomorphic (resolved at JIT time) and polymorphic (dispatch in trampoline) paths
