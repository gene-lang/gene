# Native Compilation: End-to-End Example

This document traces how a typed Gene function is compiled to native machine code and called by the VM, using a concrete example.

## Source Code

```gene
(fn f [a: Int] -> Int
  (if (a <= 1)
    a
  else
    ((f (a - 1)) + (f (a - 2)))
  )
)

(println (f 10))
```

Run with the `--native-code` flag:

```bash
bin/gene run --native-code examples/fibonacci.gene
```

## Phase 1: Parsing Type Annotations

When the parser encounters `[a: Int]`, it produces an array value containing:

```
[Symbol("a:"), Symbol("Int")]
```

The trailing `:` on `a:` signals that the next element is a type annotation.

## Phase 2: Function Construction (`value_core.nim`)

`to_function` processes the parsed Gene node. Two internal procs handle type annotations:

### `strip_type_annotations`

Walks the argument array. When it sees a symbol ending with `:`, it:
1. Strips the `:` suffix to get the parameter name (`a`)
2. Records the next symbol as the type name (`Int`) into a `type_map`
3. Returns a cleaned argument array with annotations removed

```
Input:  [Symbol("a:"), Symbol("Int")]
Output: [Symbol("a")]
type_map: {"a": "Int"}
```

### `apply_type_annotations`

Applies the collected type map to the function's `RootMatcher`:

```nim
for child in matcher.children:
  let name = cast[Value](child.name_key).str
  if type_map.hasKey(name):
    child.type_name = type_map[name]       # "Int"
    matcher.has_type_annotations = true     # enables native path
```

It also sets `matcher.hint_mode = MhDefault` to disable the fast-path argument optimization, ensuring `process_args_core` runs for runtime type validation.

After this phase, the `Function` object has:
- `matcher.has_type_annotations = true`
- `matcher.children[0].type_name = "Int"`
- `native_ready = false`, `native_failed = false`, `native_entry = nil`

## Phase 3: Bytecode Compilation (`compiler.nim`)

The compiler emits bytecode for `f` as usual. The type annotations do not change the bytecode. For the body `(if (a <= 1) a else (+ (f (- a 1)) (f (- a 2))))`, the compiler produces optimized instructions like:

```
IkVarLeValue  var[0], Data(1)    # a <= 1
IkJumpIfFalse -> else_branch
IkVarResolve  var[0]             # push a
IkJump        -> end
IkVarSubValue var[0], Data(1)    # a - 1
IkResolveSymbol "f"
IkUnifiedCall1                   # f(a - 1)
IkVarSubValue var[0], Data(2)    # a - 2
IkResolveSymbol "f"
IkUnifiedCall1                   # f(a - 2)
IkAdd                            # +
IkEnd
```

The `CompilationUnit` stores both the instructions and the matcher (with type annotations).

## Phase 4: First Call Triggers Native Compilation

When the VM executes `(f 10)`, it hits the `IkUnifiedCall1` handler in `vm.nim`. The dispatch path:

```
IkUnifiedCall1
  └─ target is VkFunction
       └─ try_native_call(vm, f, @[10], out_value)
```

### `try_native_call` (`vm.nim`)

```
1. Check vm.native_code == true           (set by --native-code flag)
2. Check f is not generator/async/macro
3. Call native_args_supported(f, args):
   a. f.matcher.has_type_annotations == true   ✓
   b. matcher.children.len == args.len == 1    ✓
   c. args.len <= 6 (x86-64) or 8 (arm64)      ✓
   d. child.type_name == "int"                 ✓
   e. args[0].kind == VkInt                    ✓
4. f.native_ready == false, so compile:
   a. Compile bytecode if not yet compiled
   b. Call compile_to_native(f.body_compiled, "f")
```

### `compile_to_native` (`native/runtime.nim`)

```
1. isNativeEligible(cu, "f")
   a. matcher.has_type_annotations == true      ✓
   b. All param type_names map to HtI64         ✓
   c. All instructions are in the supported set ✓
   d. Only local variable access (no closures)  ✓
   e. Only self-recursive calls                 ✓
2. bytecodeToHir(cu, "f")  →  HIR function
3. validate_hir(hir)       →  true
4. generateCode(hir)       →  machine code bytes
5. make_executable(code)   →  executable memory pointer
```

## Phase 5: Bytecode to HIR (`native/bytecode_to_hir.nim`)

The converter simulates the bytecode on an abstract stack, tracking which HIR register holds each value.

### Output HIR (SSA form)

```
function @f(%0: i64) -> i64 {
entry:  ; L0
    %1 = const.i64 1
    %2 = le.i64 %0, %1
    br %2, L1, L2
then_4:  ; L1
    ret %0
else_7:  ; L2
    %3 = sub.i64 %0, %1
    %4 = call @f(%3) : i64
    %5 = const.i64 2
    %6 = sub.i64 %0, %5
    %7 = call @f(%6) : i64
    %8 = add.i64 %4, %7
    ret %8
}
```

Key properties:
- **SSA form**: each `%N` register is assigned exactly once
- **Typed**: all registers are `i64` (unboxed)
- **No NaN boxing**: values are raw integers inside the native function
- **Self-recursive calls**: `call @f(...)` will become direct jumps to the function entry

## Phase 6: Machine Code Generation

The codegen backend (selected at compile time) translates HIR to native instructions.

### x86-64 (`native/x86_64_codegen.nim`)

All HIR registers are stored on the stack at `[rbp - 8*(reg+1)]`. Operations load from stack into physical registers, compute, and store back.

Generated assembly (conceptual):

```asm
_f:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 80              # 9 HIR regs * 8, aligned to 16

    # Store parameter: %0 = rdi
    mov     [rbp-8], rdi

entry:
    # %1 = const.i64 1
    mov     rax, 1
    mov     [rbp-16], rax

    # %2 = le.i64 %0, %1
    mov     rax, [rbp-8]
    mov     rcx, [rbp-16]
    cmp     rax, rcx
    setle   al
    movzx   rax, al
    mov     [rbp-24], rax

    # br %2, then, else
    mov     rax, [rbp-24]
    test    rax, rax
    je      else_block
    jmp     then_block

then_block:
    # ret %0
    mov     rax, [rbp-8]
    mov     rsp, rbp
    pop     rbp
    ret

else_block:
    # %3 = sub.i64 %0, %1
    mov     rax, [rbp-8]
    mov     rcx, [rbp-16]
    sub     rax, rcx
    mov     [rbp-32], rax

    # %4 = call @f(%3)
    mov     rdi, [rbp-32]
    call    _f                   # recursive - patched to function entry
    mov     [rbp-40], rax

    # %5 = const.i64 2
    mov     rax, 2
    mov     [rbp-48], rax

    # %6 = sub.i64 %0, %5
    mov     rax, [rbp-8]
    mov     rcx, [rbp-48]
    sub     rax, rcx
    mov     [rbp-56], rax

    # %7 = call @f(%6)
    mov     rdi, [rbp-56]
    call    _f
    mov     [rbp-64], rax

    # %8 = add.i64 %4, %7
    mov     rax, [rbp-40]
    mov     rcx, [rbp-64]
    add     rax, rcx
    mov     [rbp-72], rax

    # ret %8
    mov     rax, [rbp-72]
    mov     rsp, rbp
    pop     rbp
    ret
```

### ARM64 (`native/arm64_codegen.nim`)

Same HIR, but using ARM64 instructions. Parameters in `x0-x7`, return in `x0`. HIR registers stored at `[sp + reg*8]`.

### Memory Allocation (`runtime.nim`)

The generated bytes are copied into executable memory via `mmap`:

```nim
let mem = mmap(nil, size, PROT_READ | PROT_WRITE | PROT_EXEC,
               MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0)
```

On macOS, `pthread_jit_write_protect_np(0)` is called before writing, and `pthread_jit_write_protect_np(1)` after, to comply with Apple's hardened runtime. `__builtin___clear_cache` flushes the instruction cache.

The entry pointer is stored on the function: `f.native_entry = entry`, `f.native_ready = true`.

## Phase 7: Native Execution

Back in `try_native_call`, the VM calls the native code:

```nim
# For 1 argument:
out_value = cast[NativeFn1](f.native_entry)(args[0].to_int()).to_value()
```

This:
1. Unboxes the Gene `Value` argument to raw `int64` via `to_int()` (extracts from NaN-boxed representation)
2. Calls the native function pointer with the raw integer
3. Boxes the returned `int64` back to a Gene `Value` via `to_value()` (NaN-boxes it)

The native function runs entirely with unboxed `int64` values. Recursive calls within the native code call directly to the function entry point - no VM involvement, no boxing/unboxing, no stack frame setup.

## Phase 8: Subsequent Calls

On the second and later calls to `f`, `native_ready` is already `true`. The VM skips compilation and calls the native entry point directly. The only overhead per call is:
- `native_args_supported` check (type validation)
- Unbox arguments
- Native function call
- Box result

## Data Flow Summary

```
Gene Source
  │
  ▼
Parser ─── [a: Int] ──► type_map: {"a": "Int"}
  │
  ▼
to_function ──► Function with matcher.has_type_annotations = true
  │                                    matcher.children[0].type_name = "Int"
  ▼
Compiler ──► CompilationUnit (bytecode + matcher with type info)
  │
  ▼  (first call with --native-code)
  │
  ├─► isNativeEligible? ──► yes
  │
  ├─► bytecodeToHir ──► HirFunction (SSA, typed, unboxed)
  │
  ├─► generateCode ──► seq[byte] (x86-64 or ARM64 machine code)
  │
  ├─► make_executable ──► pointer to executable memory
  │
  ▼
VM call site:
  unbox args ──► native_entry(raw_int64) ──► box result ──► push to VM stack
```

## Eligibility Requirements

A function is compiled natively only if ALL of these hold:

| Requirement | Checked by |
|---|---|
| `--native-code` flag passed | `try_native_call` |
| Not a generator, async, or macro | `try_native_call` |
| `matcher.has_type_annotations` is true | `native_args_supported` |
| All parameter types are `Int` / `Int64` / `I64` | `native_args_supported` |
| All actual arguments are `VkInt` | `native_args_supported` |
| Argument count <= ABI limit (6 on x86-64, 8 on ARM64) | `native_args_supported` |
| All parameter types map to `HtI64` | `isNativeEligible` |
| Only local variable access (no closures) | `isNativeEligible` |
| Only supported bytecode instructions | `isNativeEligible` |
| Only self-recursive function calls | `isNativeEligible` |
| Only integer literals and operations | `isNativeEligible` |

If any check fails, the VM silently falls back to bytecode interpretation.
