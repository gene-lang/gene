# JIT Compilation Design for Gene

## Executive Summary

This document outlines the design and implementation plan for adding Just-In-Time (JIT) compilation to Gene. JIT compilation can improve performance by **10-100x** by compiling hot functions to native machine code instead of interpreting bytecode.

**Current Performance:** 3.76M function calls/sec (fib24)
**Target Performance:** 50-150M calls/sec (approaching V8/Node.js levels)

**Recommended Approach:** Direct code generation (skip templates)

## Table of Contents

1. [What is JIT Compilation?](#what-is-jit-compilation)
2. [Why Gene Needs JIT](#why-gene-needs-jit)
3. [Why Not Templates?](#why-not-templates)
4. [Direct Code Generation Approach](#direct-code-generation-approach)
5. [Implementation Phases](#implementation-phases)
6. [Technical Deep Dive](#technical-deep-dive)
7. [Code Examples](#code-examples)
8. [Challenges and Solutions](#challenges-and-solutions)
9. [Testing Strategy](#testing-strategy)
10. [Performance Expectations](#performance-expectations)

---

## What is JIT Compilation?

### Traditional Interpretation (Gene Current)

```
Gene Source → Parser → AST → Compiler → Bytecode → VM Interpreter
                                                        ↓
                                        Interpret each instruction
                                        Check types at runtime
                                        Call handlers for each opcode
```

**Performance:** Every instruction pays interpretation overhead (fetch, decode, dispatch, execute)

### JIT Compilation

```
Gene Source → Parser → AST → Compiler → Bytecode → VM Interpreter
                                                        ↓
                                            [Hot Function Detected]
                                                        ↓
                                            JIT Compiler
                                                        ↓
                                            Native Machine Code
                                                        ↓
                                            Direct CPU Execution (No interpretation!)
```

**Performance:** Hot functions run at native CPU speed

### Key Concepts

**Hot Function Detection:**
- Count how many times each function is called
- When count exceeds threshold (e.g., 100 calls), trigger JIT compilation
- Only compile the 1% of code that runs 99% of the time

**Native Machine Code:**
- JS engines do **NOT** compile to C (too slow)
- They compile directly to CPU instructions (x86-64, ARM64)
- C compilation takes seconds; JIT compilation takes milliseconds
- Example: `(a + b)` becomes `add rax, rbx` (one CPU instruction)

---

## Why Gene Needs JIT

### Current Bottlenecks

From profiling fib(24) - 150,049 function calls:

1. **Interpretation Overhead (~60% of time)**
   - Fetch instruction from bytecode array
   - Decode instruction kind
   - Dispatch to handler (even with computed goto)
   - Execute handler
   - Repeat for next instruction

   **With JIT:** Zero overhead - CPU executes native code directly

2. **Runtime Type Checking (~20% of time)**
   ```nim
   # Current: Every addition checks types
   proc execute_add(vm: VM):
     let b = pop()
     let a = pop()
     if a.kind == VkInt and b.kind == VkInt:
       push((a.int + b.int).to_value())
     elif a.kind == VkFloat or b.kind == VkFloat:
       push((to_float(a) + to_float(b)).to_value())
     # ... more type combinations
   ```

   **With JIT + Type Specialization:**
   ```asm
   ; After seeing add() only receives integers:
   pop rbx        ; Get b (no type check!)
   pop rax        ; Get a (no type check!)
   add rax, rbx   ; Direct CPU addition
   push rax       ; Push result
   ```

3. **Function Call Overhead (~15% of time)**
   - Create stack frame (even with pooling)
   - Marshal arguments
   - Save/restore registers
   - Return value handling

   **With JIT + Inlining:** Function calls eliminated entirely for small functions

4. **Memory Allocation (~5% of time)**
   - Even with pooling, frame allocation has overhead

   **With JIT + Escape Analysis:** Stack-allocate non-escaping objects

### Performance Gap

Current Gene vs Node.js on fib(24):
- **Gene:** 430ms → 3.76M calls/sec
- **Node.js:** 0.53ms → 281M calls/sec
- **Gap:** 74x slower

**Why?** Node.js uses V8's optimizing JIT compiler that eliminates all the bottlenecks above.

---

## Why Not Templates?

Templates were my initial recommendation, but they have fundamental problems:

### Problem 1: Function-Specific Templates Are Useless

```nim
# Template for fib(n) - only helps ONE function
TEMPLATE_FIB = [
  0x55,  # push rbp
  0x48, 0x89, 0xE5,  # mov rbp, rsp
  # ... fib-specific logic
]
```

**Issue:** Real code doesn't look like fib. This template helps exactly one benchmark and nothing else.

### Problem 2: Generic Templates Are Too Complex

```nim
# Attempt at generic recursive template
type RecursiveTemplate = object
  base_case_compare: CompareOp     # <, <=, ==, etc.
  base_case_value: int
  base_case_result: BaseResult
  recursive_op: BinaryOp           # +, *, -, etc.
  arg_modify_1: ArgModify          # n-1, n-2, n/2
  arg_modify_2: ArgModify
  # ... 10+ more parameters
```

**Issue:** If you need this many parameters, you're basically describing the function in a different format. At this point, just generate code from bytecode!

### Problem 3: Limited Coverage

```nim
# Even with 10 templates, you only cover:
- Simple recursion (fib, factorial)
- Basic arithmetic
- Simple loops
- Comparisons

# Real code has:
- Complex control flow
- Multiple function calls
- Map/array operations
- String manipulation
- Object property access
- Exception handling
- Async/await
# ... Templates can't handle this variety
```

### What Real VMs Do

**V8 (Node.js):** No templates. Direct code generation from bytecode.

**LuaJIT:** Uses "superinstructions" (not function templates):
```nim
# Not: "Template for fib function"
# But: "Combine these 3 instructions into 1"

# Instead of:
IkLoadVar "x"
IkPushValue 2
IkLt

# Create:
IkLoadVarCmpImm "x", 2, Lt

# This reduces dispatch overhead but is very different from function templates
```

**JavaScriptCore:** Simple "baseline JIT" (direct translation), then optimizing JIT (no templates)

### Decision: Skip Templates

**Templates add complexity without enough benefit:**
- Function templates: Too specific
- Generic templates: Too complex
- Superinstructions: Marginal gain (5-10%) vs Gene's computed goto dispatch

**Instead:** Go straight to direct code generation
- Handles all code uniformly
- Not much more complex than templates
- More maintainable (one code path)
- Easier to optimize incrementally

---

## Direct Code Generation Approach

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Bytecode Instructions                                   │
│   IkPushValue(10)                                       │
│   IkVarResolve("n")                                     │
│   IkLt                                                  │
│   IkJumpIfFalse(label_3)                                │
│   ...                                                   │
└─────────────────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ JIT Code Generator                                      │
│   for each instruction:                                 │
│     case instruction.kind:                              │
│       of IkPushValue: emit_push_imm()                   │
│       of IkVarResolve: emit_load_var()                  │
│       of IkLt: emit_compare_lt()                        │
│       ...                                               │
└─────────────────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ Native Machine Code (x86-64)                            │
│   mov rax, 10                                           │
│   push rax                                              │
│   mov rax, [rbp-8]     ; load n                         │
│   push rax                                              │
│   pop rbx                                               │
│   pop rax                                               │
│   cmp rax, rbx                                          │
│   jge label_3                                           │
│   ...                                                   │
└─────────────────────────────────────────────────────────┘
```

### Core Components

```nim
# src/gene/jit/types.nim
type
  JitCodeGen* = object
    code*: seq[uint8]              # Generated machine code
    labels*: Table[Label, int]     # Label -> code offset
    relocations*: seq[Relocation]  # Addresses to patch later
    stack_depth*: int              # Track virtual stack depth

  Relocation* = object
    offset*: int        # Where in code to patch
    kind*: RelKind      # Call, Jump, Constant
    target*: Value      # What to patch with

# src/gene/jit/x64.nim - Instruction encoders
proc emit_push_imm*(cg: var JitCodeGen, value: int64)
proc emit_push_reg*(cg: var JitCodeGen, reg: Register)
proc emit_pop_reg*(cg: var JitCodeGen, reg: Register)
proc emit_mov_reg_imm*(cg: var JitCodeGen, reg: Register, imm: int64)
proc emit_mov_reg_reg*(cg: var JitCodeGen, dst, src: Register)
proc emit_mov_reg_mem*(cg: var JitCodeGen, reg: Register, base: Register, offset: int)
proc emit_add_reg_reg*(cg: var JitCodeGen, dst, src: Register)
proc emit_cmp_reg_reg*(cg: var JitCodeGen, a, b: Register)
proc emit_jmp_rel8*(cg: var JitCodeGen, offset: int8)
proc emit_je_rel8*(cg: var JitCodeGen, offset: int8)
proc emit_call_rel32*(cg: var JitCodeGen, offset: int32)
proc emit_ret*(cg: var JitCodeGen)
# ... ~30 more instruction encoders

# src/gene/jit/compiler.nim - Main compiler
proc compile_function*(fn: Function): NativeCode
proc compile_instruction*(cg: var JitCodeGen, instr: Instruction)
```

### Instruction Encoding Example

```nim
# x86-64 instruction encoding
proc emit_add_reg_reg(cg: var JitCodeGen, dst, src: Register) =
  # add dst, src: REX.W + 0x01 + ModR/M
  cg.code.add(0x48'u8)  # REX.W prefix (64-bit operands)
  cg.code.add(0x01'u8)  # ADD opcode (r/m64, r64)

  # ModR/M byte: mod=11 (register direct), reg=src, r/m=dst
  let modrm = 0xC0'u8 or (src.ord.uint8 shl 3) or dst.ord.uint8
  cg.code.add(modrm)

# Usage:
var cg = JitCodeGen()
cg.emit_add_reg_reg(RAX, RBX)  # Generates: 48 01 D8 (add rax, rbx)
```

### Compilation Strategy

**Tier 0: Interpreter** (All code starts here)
- Fast startup
- Collect profiling data
- Count function calls

**Tier 1: Baseline JIT** (Hot functions: 100+ calls)
- Direct bytecode → assembly translation
- No optimization
- Fast compilation (microseconds)
- 10-20x speedup

**Tier 2: Optimizing JIT** (Very hot: 1000+ calls)
- Type specialization
- Function inlining
- Dead code elimination
- 50-100x speedup

---

## Implementation Phases

### Phase 1: Infrastructure (2 weeks)

**Goal:** Profiling and JIT framework without actual code generation

**Deliverables:**
```nim
# src/gene/jit/profiler.nim
type
  Profiler* = object
    call_counts*: Table[int, int64]  # function_id -> count
    hot_threshold*: int              # Default: 100
    very_hot_threshold*: int         # Default: 1000

proc record_call*(prof: var Profiler, fn: Function)
proc is_hot*(prof: Profiler, fn: Function): bool
proc is_very_hot*(prof: Profiler, fn: Function): bool

# src/gene/jit/memory.nim
proc allocate_executable_memory*(size: int): pointer
proc make_executable*(addr: pointer, size: int)
proc free_executable_memory*(addr: pointer, size: int)

# src/gene/vm.nim - Integration hooks
of IkUnifiedCall1:
  if vm.jit_enabled:
    vm.profiler.record_call(fn)

    if fn.jit_compiled != nil:
      # Call compiled version
      return call_native(fn.jit_compiled, args)

    if vm.profiler.is_hot(fn):
      # Trigger compilation
      fn.jit_compiled = vm.jit_compiler.compile(fn)

  # Fall back to interpreter
  # ... existing code
```

**Testing:**
- Profiler correctly counts calls
- Hot function detection works
- Memory allocation/protection works
- Integration doesn't break interpreter

---

### Phase 2: Basic Code Generation (4 weeks)

**Goal:** Compile simple functions to native code

**Instruction Encoders to Implement (~30 total):**

**Stack Operations:**
- `emit_push_imm` - Push immediate value
- `emit_push_reg` - Push register
- `emit_pop_reg` - Pop to register

**Data Movement:**
- `emit_mov_reg_imm` - Load immediate into register
- `emit_mov_reg_reg` - Move between registers
- `emit_mov_reg_mem` - Load from memory
- `emit_mov_mem_reg` - Store to memory

**Arithmetic:**
- `emit_add_reg_reg` - Add two registers
- `emit_sub_reg_reg` - Subtract
- `emit_mul_reg_reg` - Multiply (uses imul)
- `emit_div_reg_reg` - Divide (uses idiv, complex!)
- `emit_neg_reg` - Negate

**Comparison:**
- `emit_cmp_reg_reg` - Compare two registers
- `emit_test_reg_reg` - Bitwise test

**Control Flow:**
- `emit_jmp_rel8/rel32` - Unconditional jump
- `emit_je/jne/jl/jle/jg/jge` - Conditional jumps
- `emit_call_rel32` - Function call
- `emit_ret` - Return

**Compiler Logic:**
```nim
proc compile_function(fn: Function): NativeCode =
  var cg = JitCodeGen()

  # Function prologue
  cg.emit_push_reg(RBP)
  cg.emit_mov_reg_reg(RBP, RSP)

  # Reserve stack space for locals if needed
  if fn.local_count > 0:
    cg.emit_sub_reg_imm(RSP, fn.local_count * 8)

  # Compile each bytecode instruction
  for instr in fn.bytecode:
    compile_instruction(cg, instr)

  # Function epilogue
  cg.emit_mov_reg_reg(RSP, RBP)
  cg.emit_pop_reg(RBP)
  cg.emit_ret()

  # Resolve relocations (patch call/jump addresses)
  resolve_relocations(cg)

  return make_executable(cg.code)

proc compile_instruction(cg: var JitCodeGen, instr: Instruction) =
  case instr.kind:
    of IkPushValue:
      if instr.arg0.kind == VkInt:
        cg.emit_push_imm(instr.arg0.int)
      else:
        # Complex value - call interpreter helper
        cg.emit_call_helper("push_value", instr.arg0)

    of IkVarResolve:
      # Load from stack frame at offset
      let offset = -8 * (instr.arg0.int + 1)
      cg.emit_mov_reg_mem(RAX, RBP, offset)
      cg.emit_push_reg(RAX)

    of IkAdd:
      cg.emit_pop_reg(RBX)
      cg.emit_pop_reg(RAX)
      cg.emit_add_reg_reg(RAX, RBX)
      cg.emit_push_reg(RAX)

    of IkLt:
      cg.emit_pop_reg(RBX)
      cg.emit_pop_reg(RAX)
      cg.emit_cmp_reg_reg(RAX, RBX)
      # Set AL to 1 if less than, 0 otherwise
      cg.emit_setl(AL)
      cg.emit_movzx(RAX, AL)  # Zero-extend AL to RAX
      cg.emit_push_reg(RAX)

    of IkJumpIfFalse:
      cg.emit_pop_reg(RAX)
      cg.emit_test_reg_reg(RAX, RAX)
      cg.emit_je_label(instr.label)  # Jump if zero

    of IkReturn:
      cg.emit_pop_reg(RAX)  # Return value in RAX
      cg.emit_mov_reg_reg(RSP, RBP)
      cg.emit_pop_reg(RBP)
      cg.emit_ret()

    # ... more instructions
```

**Testing:**
- Compile and run simple functions (add, subtract, multiply)
- Correctness: JIT results == interpreter results
- Performance: Measure speedup

**Expected Outcome:** 10-20x speedup on fib(24)

---

### Phase 3: Type Specialization (3 weeks)

**Goal:** Generate specialized versions based on observed types

**Type Feedback Collection:**
```nim
type
  TypeFeedback* = object
    function_id*: int
    signatures*: Table[string, SignatureStats]
    total_calls*: int64

  SignatureStats* = object
    arg_types*: seq[ValueKind]
    return_type*: ValueKind
    count*: int64

proc collect_type_feedback(vm: VM, fn: Function, args: seq[Value]) =
  var feedback = vm.get_feedback(fn.id)

  # Build type signature
  var sig = newSeq[ValueKind](args.len)
  for i, arg in args:
    sig[i] = arg.kind

  let sig_str = sig.map(k => $k).join(",")

  if sig_str in feedback.signatures:
    feedback.signatures[sig_str].count.inc()
  else:
    feedback.signatures[sig_str] = SignatureStats(
      arg_types: sig,
      count: 1
    )

  feedback.total_calls.inc()

  # If one signature dominates (>90%), specialize
  for sig_str, stats in feedback.signatures:
    if stats.count > (feedback.total_calls * 9 div 10):
      trigger_specialized_compilation(fn, stats.arg_types)
```

**Specialized Compilation:**
```nim
proc compile_specialized(fn: Function, arg_types: seq[ValueKind]): NativeCode =
  var cg = JitCodeGen()
  cg.specialized_types = arg_types  # Store for later use

  # Prologue with type guards
  cg.emit_prologue()

  # Guard: Check that actual types match expected types
  for i, expected in arg_types:
    cg.emit_type_guard(arg_registers[i], expected)

  # Compile with type knowledge
  for instr in fn.bytecode:
    compile_instruction_specialized(cg, instr, arg_types)

  cg.emit_epilogue()
  return make_executable(cg.code)

proc compile_instruction_specialized(cg: var JitCodeGen, instr: Instruction, types: seq[ValueKind]) =
  case instr.kind:
    of IkAdd:
      # We KNOW both operands are integers (from type feedback)
      cg.emit_pop_reg(RBX)
      cg.emit_pop_reg(RAX)
      # No type check needed!
      cg.emit_add_reg_reg(RAX, RBX)
      # Check for overflow (optional)
      cg.emit_jo_deoptimize()  # Jump to deopt if overflow
      cg.emit_push_reg(RAX)

    # ... more specialized compilations
```

**Type Guards and Deoptimization:**
```nim
proc emit_type_guard(cg: var JitCodeGen, reg: Register, expected: ValueKind) =
  # Check value type (NaN-boxed value)
  cg.emit_mov_reg_reg(RAX, reg)
  cg.emit_shr_reg_imm(RAX, 48)  # Get type tag
  cg.emit_cmp_reg_imm(RAX, expected.ord)
  cg.emit_jne_label(".deoptimize")

proc emit_deoptimize_stub(cg: var JitCodeGen, fn: Function) =
  cg.emit_label(".deoptimize")
  # Save current state
  cg.emit_push_all_regs()
  # Call deoptimization handler
  cg.emit_call_helper("deoptimize", fn.id)
  # Handler will:
  #   1. Mark JIT code as invalid
  #   2. Restore interpreter state
  #   3. Continue in interpreter
```

**Expected Outcome:** 20-30x speedup (fewer type checks, better CPU optimization)

---

### Phase 4: Function Inlining (3 weeks)

**Goal:** Inline small hot functions at call sites

**Inlining Decision:**
```nim
proc should_inline(caller: Function, callee: Function): bool =
  # Size heuristic
  if callee.bytecode.len > 50:
    return false  # Too large

  # Frequency heuristic
  let call_count = get_call_count(caller, callee)
  if call_count < 10:
    return false  # Not called often enough

  # Recursion check
  if is_recursive(callee):
    return false  # Can't inline recursive functions

  # Cost/benefit
  let frame_overhead = 20  # cycles
  let potential_savings = call_count * frame_overhead
  return potential_savings > 100

proc inline_function(cg: var JitCodeGen, callee: Function, call_site: int) =
  # Instead of: call callee_address
  # Generate: [callee code inline]

  # Save current position
  let saved_labels = cg.labels

  # Compile callee body inline
  for instr in callee.bytecode:
    case instr.kind:
      of IkReturn:
        # Don't emit return - continue with caller
        discard
      else:
        compile_instruction(cg, instr)

  # Restore label context
  cg.labels = saved_labels
```

**Expected Outcome:** 30-50x speedup (eliminated call overhead)

---

### Phase 5: Advanced Optimizations (4+ weeks)

**Optimizations to Implement:**

1. **Dead Code Elimination**
   ```nim
   # Before
   var x = 10
   x = 20
   return x  # x=10 assignment is dead

   # After
   var x = 20
   return x
   ```

2. **Constant Folding**
   ```nim
   # Before
   var x = 2 + 3

   # After
   var x = 5
   ```

3. **Common Subexpression Elimination**
   ```nim
   # Before
   var a = x * y
   var b = x * y

   # After
   var tmp = x * y
   var a = tmp
   var b = tmp
   ```

4. **Loop Optimizations**
   - Loop unrolling
   - Loop invariant code motion
   - Strength reduction

5. **Escape Analysis**
   - Stack-allocate objects that don't escape
   - Eliminate unnecessary allocations

**Expected Outcome:** 50-100x speedup (approaching V8)

---

## Technical Deep Dive

### x86-64 Instruction Encoding

**Anatomy of an x86-64 Instruction:**
```
[Prefix] [REX] [Opcode] [ModR/M] [SIB] [Displacement] [Immediate]
   ↑      ↑       ↑        ↑       ↑         ↑             ↑
Optional Optional Required Optional Optional Optional   Optional
```

**Example: `add rax, rbx`**
```
Bytes: 48 01 D8

48     = REX.W prefix (64-bit operands)
01     = ADD opcode (r/m64, r64)
D8     = ModR/M byte
         D8 = 11011000 binary
         - mod=11 (register direct addressing)
         - reg=011 (rbx = source)
         - r/m=000 (rax = destination)
```

**Implementing the Encoder:**
```nim
type
  Register = enum
    RAX = 0, RCX = 1, RDX = 2, RBX = 3,
    RSP = 4, RBP = 5, RSI = 6, RDI = 7,
    R8  = 8, R9  = 9, R10 = 10, R11 = 11,
    R12 = 12, R13 = 13, R14 = 14, R15 = 15

proc emit_add_reg_reg(cg: var JitCodeGen, dst, src: Register) =
  # REX.W prefix for 64-bit
  var rex = 0x48'u8

  # REX.R bit if src register is R8-R15
  if src.ord >= 8:
    rex = rex or 0x04

  # REX.B bit if dst register is R8-R15
  if dst.ord >= 8:
    rex = rex or 0x01

  cg.code.add(rex)

  # ADD opcode
  cg.code.add(0x01'u8)

  # ModR/M byte
  let modrm = 0xC0'u8 or
              ((src.ord and 0x7).uint8 shl 3) or
              ((dst.ord and 0x7).uint8)
  cg.code.add(modrm)
```

### Memory Management

**Executable Memory Allocation:**
```nim
when defined(posix):
  import posix

  proc allocate_executable_memory(size: int): pointer =
    # Round up to page size
    let page_size = 4096
    let alloc_size = (size + page_size - 1) and not (page_size - 1)

    # Allocate with mmap
    let addr = mmap(
      nil,                           # Let OS choose address
      alloc_size,
      PROT_READ or PROT_WRITE,      # Initially writable
      MAP_PRIVATE or MAP_ANONYMOUS,  # Private, not file-backed
      -1,                            # No file descriptor
      0                              # No offset
    )

    if addr == MAP_FAILED:
      raise newException(OutOfMemoryError, "Cannot allocate JIT memory")

    return addr

  proc make_executable(addr: pointer, size: int) =
    # Change to read+execute (no write)
    if mprotect(addr, size, PROT_READ or PROT_EXEC) != 0:
      raise newException(OSError, "Cannot make memory executable")

elif defined(windows):
  import winlean

  proc allocate_executable_memory(size: int): pointer =
    VirtualAlloc(
      nil,
      size,
      MEM_COMMIT or MEM_RESERVE,
      PAGE_READWRITE
    )

  proc make_executable(addr: pointer, size: int) =
    var old_protect: DWORD
    VirtualProtect(addr, size, PAGE_EXECUTE_READ, old_protect.addr)
```

**Memory Pool Management:**
```nim
type
  JitMemoryPool = object
    pages: seq[JitPage]
    page_size: int

  JitPage = object
    address: pointer
    size: int
    used: int
    functions: seq[JitFunction]

proc allocate_from_pool(pool: var JitMemoryPool, size: int): pointer =
  # Try to find page with enough space
  for page in pool.pages.mitems:
    if page.used + size <= page.size:
      result = cast[pointer](cast[uint](page.address) + page.used.uint)
      page.used += size
      return

  # Need new page
  let new_page = JitPage(
    address: allocate_executable_memory(pool.page_size),
    size: pool.page_size,
    used: size
  )
  pool.pages.add(new_page)
  return new_page.address
```

### Calling Convention (System V AMD64 ABI)

**Used on Linux and macOS:**

```
Integer/Pointer Arguments: RDI, RSI, RDX, RCX, R8, R9 (then stack)
Float Arguments: XMM0-XMM7 (then stack)
Return Value: RAX (integer), XMM0 (float)
Caller-saved: RAX, RCX, RDX, RSI, RDI, R8-R11
Callee-saved: RBX, RBP, R12-R15
Stack Alignment: 16 bytes at call instruction
```

**Implications for JIT:**
```nim
proc emit_function_prologue(cg: var JitCodeGen) =
  # Save callee-saved registers we'll use
  cg.emit_push_reg(RBP)
  cg.emit_mov_reg_reg(RBP, RSP)
  cg.emit_push_reg(RBX)
  cg.emit_push_reg(R12)
  # ... more if needed

  # Ensure 16-byte stack alignment
  # RSP must be 16-byte aligned before any call instruction
  let alignment_adjust = (16 - (cg.stack_depth mod 16)) mod 16
  if alignment_adjust > 0:
    cg.emit_sub_reg_imm(RSP, alignment_adjust)

proc emit_function_call(cg: var JitCodeGen, target: Function, args: seq[Value]) =
  # Marshal arguments to registers/stack
  const arg_regs = [RDI, RSI, RDX, RCX, R8, R9]

  for i, arg in args:
    if i < 6:
      # Load into register
      cg.load_value_to_reg(arg_regs[i], arg)
    else:
      # Push to stack (in reverse order)
      cg.push_value(arg)

  # Make the call
  cg.emit_call_rel32(target.address)

  # Clean up stack arguments if any
  if args.len > 6:
    let stack_args = args.len - 6
    cg.emit_add_reg_imm(RSP, stack_args * 8)
```

### Cache Flushing

**x86-64:** Instruction cache is coherent with data cache (no flush needed)

**ARM64:** Explicit cache flush required:
```nim
when defined(arm64):
  proc flush_instruction_cache(address: pointer, size: int) =
    # DC CVAU - Clean data cache to point of unification
    # DSB ISH - Data synchronization barrier
    # IC IVAU - Invalidate instruction cache
    # DSB ISH - Another barrier
    # ISB - Instruction synchronization barrier
    asm """
      dc cvau, %0
      dsb ish
      ic ivau, %0
      dsb ish
      isb
      :
      : "r"(`address`)
    """
```

### Deoptimization

**When JIT assumptions break:**
```nim
# Example: JIT assumes add() receives integers
# Later: add("hello", "world") is called

# Generated code includes guards:
proc emit_guarded_add(cg: var JitCodeGen) =
  # Guard: Check both operands are integers
  cg.emit_pop_reg(RBX)
  cg.emit_pop_reg(RAX)

  # Check RAX is integer
  cg.emit_mov_reg_reg(RCX, RAX)
  cg.emit_and_reg_imm(RCX, TYPE_MASK)
  cg.emit_cmp_reg_imm(RCX, VkInt)
  cg.emit_jne(".deopt")

  # Check RBX is integer
  cg.emit_mov_reg_reg(RCX, RBX)
  cg.emit_and_reg_imm(RCX, TYPE_MASK)
  cg.emit_cmp_reg_imm(RCX, VkInt)
  cg.emit_jne(".deopt")

  # Fast path: Both integers
  cg.emit_add_reg_reg(RAX, RBX)
  cg.emit_push_reg(RAX)
  cg.emit_ret()

  # Slow path: Type mismatch
  cg.emit_label(".deopt")
  # Push values back
  cg.emit_push_reg(RAX)
  cg.emit_push_reg(RBX)
  # Call interpreter
  cg.emit_call("interpret_add")
  cg.emit_ret()
```

---

## Code Examples

### Complete Minimal JIT

```nim
# src/gene/jit/minimal.nim
import tables

type
  Register = enum
    RAX = 0, RBX = 3, RCX = 1, RDX = 2

  CodeGen = object
    code: seq[uint8]
    labels: Table[int, int]  # label -> offset

# Instruction encoders
proc emit(cg: var CodeGen, bytes: openArray[uint8]) =
  for b in bytes:
    cg.code.add(b)

proc emit_push_imm(cg: var CodeGen, value: int64) =
  # mov rax, imm64; push rax
  cg.emit([0x48'u8, 0xB8'u8])
  cg.emit(cast[array[8, uint8]](value))
  cg.emit([0x50'u8])

proc emit_push_reg(cg: var CodeGen, reg: Register) =
  cg.emit([0x50'u8 + reg.uint8])

proc emit_pop_reg(cg: var CodeGen, reg: Register) =
  cg.emit([0x58'u8 + reg.uint8])

proc emit_add(cg: var CodeGen) =
  # pop rbx; pop rax; add rax, rbx; push rax
  cg.emit([0x5B'u8])              # pop rbx
  cg.emit([0x58'u8])              # pop rax
  cg.emit([0x48'u8, 0x01'u8, 0xD8'u8])  # add rax, rbx
  cg.emit([0x50'u8])              # push rax

proc emit_ret(cg: var CodeGen) =
  cg.emit([0xC3'u8])

proc emit_cmp_imm(cg: var CodeGen, value: int8) =
  # pop rax; cmp rax, imm8
  cg.emit([0x58'u8])              # pop rax
  cg.emit([0x48'u8, 0x83'u8, 0xF8'u8, cast[uint8](value)])

proc emit_jge_rel8(cg: var CodeGen, offset: int8) =
  cg.emit([0x7D'u8, cast[uint8](offset)])

# Compiler
proc compile_function(fn: Function): seq[uint8] =
  var cg = CodeGen()

  for instr in fn.bytecode:
    case instr.kind:
      of IkPushValue:
        if instr.arg0.kind == VkInt:
          cg.emit_push_imm(instr.arg0.int)

      of IkAdd:
        cg.emit_add()

      of IkReturn:
        cg.emit_pop_reg(RAX)
        cg.emit_ret()

      else:
        discard  # Extend as needed

  return cg.code

# Make executable and run
proc jit_and_run(fn: Function): Value =
  let code = compile_function(fn)
  let mem = allocate_executable_memory(code.len)
  copyMem(mem, code[0].unsafeAddr, code.len)
  make_executable(mem, code.len)

  let native_fn = cast[proc(): int64 {.cdecl.}](mem)
  let result = native_fn()

  return result.to_value()
```

### Integration with VM

```nim
# src/gene/vm.nim modifications

type
  VirtualMachine* = ref object
    # ... existing fields
    jit_enabled*: bool
    jit_compiler*: JitCompiler
    profiler*: Profiler

# Modify function call
of IkUnifiedCall1:
  let target = self.frame.stack[self.frame.stack_index - 1]

  case target.kind:
    of VkFunction:
      let fn = target.ref.fn

      # JIT compilation path
      if self.jit_enabled:
        # Record call
        self.profiler.record_call(fn)

        # Check for compiled version
        if not fn.jit_code.is_nil:
          # Call JIT-compiled code
          let arg = self.frame.stack[self.frame.stack_index]
          let result = call_jit_function(fn.jit_code, arg)
          self.frame.stack[self.frame.stack_index - 1] = result
          self.frame.stack_index.dec()
          return

        # Should we compile?
        if self.profiler.is_hot(fn) and fn.jit_code.is_nil:
          fn.jit_code = self.jit_compiler.compile(fn)

      # Fall back to interpreter
      # ... existing interpreter code
```

---

## Challenges and Solutions

### Challenge 1: Debugging Generated Code

**Problem:** Machine code is hard to debug

**Solutions:**

1. **Disassemble generated code:**
   ```nim
   proc dump_code(code: seq[uint8], filename = "/tmp/jit.bin") =
     writeFile(filename, code)
     echo "Disassembly:"
     discard execCmd("objdump -D -b binary -m i386:x86-64 " & filename)
   ```

2. **Compare with compiler:**
   ```c
   // Write equivalent C function
   int64_t add(int64_t a, int64_t b) {
     return a + b;
   }

   // Compile with: gcc -S -O0 test.c
   // Compare assembly with JIT output
   ```

3. **Incremental testing:**
   ```nim
   # Test each instruction encoder separately
   test "emit_add generates correct bytes":
     var cg = CodeGen()
     cg.emit_add_reg_reg(RAX, RBX)
     check cg.code == @[0x48'u8, 0x01'u8, 0xD8'u8]
   ```

### Challenge 2: Cross-Platform Support

**Problem:** Different architectures (x86-64, ARM64)

**Solution:** Platform abstraction layer

```nim
type
  JitArch = enum
    JaX64, JaArm64

proc emit_add(cg: var CodeGen, arch: JitArch, dst, src: Register) =
  case arch:
    of JaX64:
      cg.code.add([0x48'u8, 0x01'u8, ...])
    of JaArm64:
      # ARM64 encoding
      cg.code.add([...])

# Start with x86-64 only
when defined(amd64):
  const CURRENT_ARCH = JaX64
elif defined(arm64):
  const CURRENT_ARCH = JaArm64
```

### Challenge 3: Correctness Testing

**Problem:** How to ensure JIT produces correct results?

**Solution:** Differential testing

```nim
proc test_jit_correctness(fn: Function, test_inputs: seq[seq[Value]]) =
  for inputs in test_inputs:
    # Run interpreted version
    let interp_result = run_interpreted(fn, inputs)

    # Run JIT version
    let jit_result = run_jit(fn, inputs)

    # Must match
    check interp_result == jit_result
```

### Challenge 4: Memory Leaks

**Problem:** JIT code allocates memory that must be freed

**Solution:** Track allocated code

```nim
type
  JitFunction = object
    code_ptr: pointer
    code_size: int
    compiled_at: Time

  JitCompiler = object
    allocated_functions: seq[JitFunction]

proc free_old_compilations(jc: var JitCompiler, max_age: Duration) =
  let now = getTime()
  var i = 0
  while i < jc.allocated_functions.len:
    if now - jc.allocated_functions[i].compiled_at > max_age:
      let jf = jc.allocated_functions[i]
      free_executable_memory(jf.code_ptr, jf.code_size)
      jc.allocated_functions.delete(i)
    else:
      i.inc()
```

---

## Testing Strategy

### Unit Tests

```nim
# tests/jit/test_encoders.nim
suite "Instruction Encoders":
  test "emit_push_imm":
    var cg = CodeGen()
    cg.emit_push_imm(42)
    # Should generate: mov rax, 42; push rax
    check cg.code[0..1] == [0x48'u8, 0xB8'u8]
    check cast[int64](cg.code[2..9]) == 42
    check cg.code[10] == 0x50'u8

  test "emit_add_reg_reg":
    var cg = CodeGen()
    cg.emit_add_reg_reg(RAX, RBX)
    check cg.code == [0x48'u8, 0x01'u8, 0xD8'u8]
```

### Integration Tests

```nim
# tests/jit/test_integration.nim
suite "JIT Integration":
  test "simple addition":
    let code = "(fn add [a b] (a + b))"
    let fn = parse_and_compile(code)

    # Compile with JIT
    let jit_fn = jit_compile(fn)

    # Test
    let result = call_jit(jit_fn, @[5.to_value(), 3.to_value()])
    check result.int == 8

  test "recursive fibonacci":
    let code = """
      (fn fib [n]
        (if (n < 2)
          n
          ((fib (n - 1)) + (fib (n - 2)))))
    """
    let fn = parse_and_compile(code)
    let jit_fn = jit_compile(fn)

    check call_jit(jit_fn, @[0.to_value()]).int == 0
    check call_jit(jit_fn, @[1.to_value()]).int == 1
    check call_jit(jit_fn, @[10.to_value()]).int == 55
```

### Differential Testing

```nim
# tests/jit/test_correctness.nim
suite "JIT Correctness":
  test "JIT matches interpreter on random inputs":
    let test_functions = [
      "(fn add [a b] (a + b))",
      "(fn mul [a b] (a * b))",
      "(fn fib [n] ...)",
      # ... more
    ]

    for code in test_functions:
      let fn = parse_and_compile(code)
      let jit_fn = jit_compile(fn)

      # Test with random inputs
      for i in 0..<100:
        let inputs = generate_random_inputs(fn.arity)
        let interp_result = run_interpreted(fn, inputs)
        let jit_result = run_jit(jit_fn, inputs)
        check interp_result == jit_result
```

### Performance Benchmarks

```nim
# benchmarks/jit_bench.nim
proc benchmark_fib24() =
  let fn = compile_fib()
  let jit_fn = jit_compile(fn)

  # Warmup
  for i in 0..<10:
    discard call_jit(jit_fn, @[10.to_value()])

  # Benchmark
  let start = cpuTime()
  for i in 0..<5:
    discard call_jit(jit_fn, @[24.to_value()])
  let duration = cpuTime() - start

  let calls_per_sec = (5 * 150_049) / duration
  echo "Calls/sec: ", calls_per_sec / 1_000_000, "M"
```

---

## Performance Expectations

### Phase-by-Phase Improvements

| Phase | Feature | Implementation | Speedup | Calls/sec | vs Node.js |
|-------|---------|----------------|---------|-----------|------------|
| **Baseline** | Interpreter | Current | 1x | 3.76M | 74x slower |
| **Phase 1** | Infrastructure | 2 weeks | 1x | 3.76M | 74x slower |
| **Phase 2** | Basic JIT | 4 weeks | **10-20x** | 40-75M | **7-3x slower** |
| **Phase 3** | Type specialization | 3 weeks | **20-30x** | 75-110M | **3.7-2.5x slower** |
| **Phase 4** | Inlining | 3 weeks | **30-50x** | 110-180M | **2.5-1.5x slower** |
| **Phase 5** | Full optimization | 4+ weeks | **50-100x** | 180-300M | **Match V8!** |

### Realistic Timeline

**Q1 2025:** Phases 1-2 (6 weeks)
- Infrastructure + Basic JIT
- 10-20x improvement
- 40-75M calls/sec
- **Proof of concept complete**

**Q2 2025:** Phase 3 (3 weeks)
- Type specialization
- 20-30x total improvement
- 75-110M calls/sec

**Q3 2025:** Phase 4 (3 weeks)
- Function inlining
- 30-50x total improvement
- 110-180M calls/sec
- **Competitive with interpreted languages**

**Q4 2025:** Phase 5 (ongoing)
- Advanced optimizations
- 50-100x total improvement
- 180-300M calls/sec
- **Competitive with V8**

### Comparison with Other Languages

After Phase 2 (Basic JIT):
```
Gene:     40-75M calls/sec
Python:   25M calls/sec    ✓ Gene faster
Ruby:     35M calls/sec    ✓ Gene faster
Lua:      50M calls/sec    ≈ Competitive
```

After Phase 5 (Full JIT):
```
Gene:     180-300M calls/sec
LuaJIT:   200M calls/sec    ✓ Competitive
Node.js:  281M calls/sec    ✓ Competitive
V8 peak:  400M+ calls/sec   - Still behind peak V8
```

---

## File Structure

```
src/gene/jit/
  ├── types.nim              # JIT types and data structures
  ├── profiler.nim           # Hot function detection
  ├── compiler.nim           # Main JIT compiler
  ├── x64/
  │   ├── types.nim         # x86-64 types (Register, etc.)
  │   ├── encoders.nim      # Instruction encoders
  │   └── abi.nim           # Calling convention
  ├── arm64/
  │   ├── types.nim         # ARM64 types
  │   ├── encoders.nim      # Instruction encoders
  │   └── abi.nim           # Calling convention
  ├── memory.nim             # Executable memory management
  ├── deopt.nim              # Deoptimization support
  └── optimizer.nim          # Optimization passes

tests/jit/
  ├── test_profiler.nim
  ├── test_memory.nim
  ├── test_encoders.nim
  ├── test_compiler.nim
  ├── test_correctness.nim   # Differential testing
  └── test_integration.nim

benchmarks/
  ├── jit_bench.nim
  └── compare_langs.sh
```

---

## References

### Academic Papers
- "A Fast Interpreter Using LLVM" - Fast JIT design
- "HotSpot JVM Internals" - Tiered compilation
- "V8: A Tale of Two Compilers" - Baseline + optimizing JIT

### Open Source Implementations
- **V8 (Chromium/Node.js)** - Industry standard
- **LuaJIT** - Extremely fast, simple design
- **JavaScriptCore** - Apple's JS engine, good documentation

### Documentation
- Intel 64/IA-32 Software Developer Manuals - x86-64 reference
- ARM Architecture Reference Manual - ARM64 reference
- System V ABI AMD64 - Calling convention
- Agner Fog's Optimization Manuals - Performance tips

### Tools
- **objdump** - Disassemble generated code
- **perf** (Linux) - Profile JIT code
- **Instruments** (macOS) - Profile JIT code
- **Compiler Explorer (godbolt.org)** - See what compilers generate

---

## Conclusion

**Direct code generation is the right approach for Gene's JIT compiler.**

**Why:**
- Templates are either too specific (fib) or too complex (generic)
- Direct codegen handles all code uniformly
- Not significantly more complex than templates
- More maintainable and extensible

**Timeline:**
- **6 weeks:** Basic JIT working (10-20x speedup)
- **12 weeks:** Type specialization (20-30x speedup)
- **16 weeks:** Function inlining (30-50x speedup)
- **20+ weeks:** Full optimization (50-100x speedup)

**Success Criteria:**
1. Phase 2 delivers 10x speedup on fib(24)
2. All JIT code passes differential tests (matches interpreter)
3. No performance regression on cold code
4. Memory usage stays reasonable (<100MB for JIT code cache)

**Next Steps:**
1. Review this design document
2. Implement Phase 1 (infrastructure)
3. Implement Phase 2 (basic JIT)
4. Measure and iterate

Gene can achieve competitive performance with modern scripting languages through systematic JIT implementation. The direct codegen approach provides the best balance of simplicity, coverage, and performance.
