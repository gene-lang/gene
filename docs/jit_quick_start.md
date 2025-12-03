# JIT Quick Start Guide

Quick reference for implementing JIT compilation in Gene. See [jit_design.md](./jit_design.md) for full details.

## TL;DR

**Goal:** 50-100x speedup through JIT compilation
**Approach:** Direct code generation (skip templates)
**Timeline:** 12-16 weeks for production-ready implementation

## Why Direct Codegen (Not Templates)?

**Templates are problematic:**
- Function-specific templates (like fib) are useless for real code
- Generic templates end up as complex as direct codegen
- Limited coverage (can't handle all code patterns)

**Direct codegen is better:**
- Handles all bytecode uniformly
- Only slightly more complex than templates
- More maintainable (one code path)
- Easier to optimize incrementally

## Quick Implementation Checklist

### Week 1-2: Infrastructure
```nim
# Add to VM
type VirtualMachine = ref object
  jit_enabled*: bool
  profiler*: Profiler
  jit_compiler*: JitCompiler

type Profiler = object
  call_counts*: Table[int, int64]
  hot_threshold*: int  # Default: 100

proc record_call(prof: var Profiler, fn: Function):
  prof.call_counts[fn.id] = prof.call_counts.getOrDefault(fn.id, 0) + 1
  if prof.call_counts[fn.id] == prof.hot_threshold:
    trigger_jit_compilation(fn)
```

### Week 3-6: Basic Code Generation
```nim
# Instruction encoders (~30 total)
proc emit_push_imm(cg: var CodeGen, value: int64)
proc emit_pop_reg(cg: var CodeGen, reg: Register)
proc emit_add_reg_reg(cg: var CodeGen, dst, src: Register)
proc emit_cmp_reg_reg(cg: var CodeGen, a, b: Register)
proc emit_jmp_label(cg: var CodeGen, label: Label)
proc emit_call_rel32(cg: var CodeGen, offset: int32)
proc emit_ret(cg: var CodeGen)
# ... ~23 more

# Main compiler
proc compile_function(fn: Function): NativeCode =
  var cg = CodeGen()

  cg.emit_prologue()

  for instr in fn.bytecode:
    compile_instruction(cg, instr)

  cg.emit_epilogue()
  return make_executable(cg.code)

proc compile_instruction(cg: var CodeGen, instr: Instruction) =
  case instr.kind:
    of IkPushValue: cg.emit_push_imm(instr.arg0.int)
    of IkAdd: cg.emit_add()
    of IkReturn: cg.emit_ret()
    # ... handle all instruction types
```

### Week 7-8: Integration
```nim
# Modify VM execution
of IkUnifiedCall1:
  if vm.jit_enabled:
    vm.profiler.record_call(fn)

    if fn.jit_code != nil:
      return call_jit(fn.jit_code, args)

    if vm.profiler.is_hot(fn):
      fn.jit_code = vm.jit_compiler.compile(fn)

  # Fall back to interpreter
```

## File Structure

```
src/gene/jit/
  ├── types.nim          # JIT data structures
  ├── profiler.nim       # Hot function detection
  ├── compiler.nim       # Main JIT compiler
  ├── x64/
  │   ├── types.nim     # x86-64 types (Register, etc.)
  │   ├── encoders.nim  # Instruction encoders
  │   └── abi.nim       # Calling convention
  ├── memory.nim         # Executable memory management
  └── optimizer.nim      # Optimization passes (later)

tests/jit/
  ├── test_encoders.nim      # Test each encoder
  ├── test_compiler.nim      # Test compilation
  ├── test_correctness.nim   # JIT vs interpreter
  └── test_integration.nim   # End-to-end tests
```

## Minimal Working Example

```nim
# Simplest possible JIT: Compile add(a, b)

type CodeGen = object
  code: seq[uint8]

proc emit_add_function(cg: var CodeGen) =
  # Prologue
  cg.code.add(0x55'u8)              # push rbp
  cg.code.add([0x48'u8, 0x89'u8, 0xE5'u8])  # mov rbp, rsp

  # Function body: add rdi, rsi (a + b)
  cg.code.add([0x48'u8, 0x89'u8, 0xF8'u8])  # mov rax, rdi (rax = a)
  cg.code.add([0x48'u8, 0x01'u8, 0xF0'u8])  # add rax, rsi (rax += b)

  # Epilogue
  cg.code.add(0x5D'u8)              # pop rbp
  cg.code.add(0xC3'u8)              # ret

# Usage
var cg = CodeGen()
cg.emit_add_function()

let mem = allocate_executable_memory(cg.code.len)
copyMem(mem, cg.code[0].addr, cg.code.len)
make_executable(mem, cg.code.len)

let add_fn = cast[proc(a, b: int64): int64 {.cdecl.}](mem)
assert add_fn(2, 3) == 5  # ✓ Native speed!
```

## x86-64 Instruction Encoding Cheatsheet

**Basic Structure:**
```
[REX prefix] [Opcode] [ModR/M] [Immediate/Displacement]
```

**Common Encodings:**
```nim
# push rbp
[0x55]

# pop rbp
[0x5D]

# mov rbp, rsp
[0x48, 0x89, 0xE5]

# push rax
[0x50]

# pop rax
[0x58]

# add rax, rbx (REX.W + ADD opcode + ModR/M)
[0x48, 0x01, 0xD8]

# cmp rax, rbx
[0x48, 0x39, 0xD8]

# ret
[0xC3]

# jmp rel8 (short jump)
[0xEB, offset]

# je rel8 (jump if equal)
[0x74, offset]

# call rel32 (relative call)
[0xE8, offset_byte0, offset_byte1, offset_byte2, offset_byte3]
```

**ModR/M Byte Format:**
```
Bits: [mod:2] [reg:3] [r/m:3]

mod = 11 (register-to-register)
reg = source register
r/m = destination register

Example: add rax, rbx
  mod = 11 (register direct)
  reg = 011 (rbx)
  r/m = 000 (rax)
  Result: 11011000 = 0xD8
```

## Performance Targets

| Milestone | Technique | Speedup | Timeline |
|-----------|-----------|---------|----------|
| Infrastructure | Profiling + framework | 1x | 2 weeks |
| Basic JIT | Direct codegen | **10-20x** | 6 weeks total |
| Type specialization | Observed types | **20-30x** | 9 weeks total |
| Function inlining | Inline hot calls | **30-50x** | 12 weeks total |
| Full optimization | DCE, CSE, etc. | **50-100x** | 16+ weeks total |

## Common Pitfalls

❌ **Don't:** Try to optimize interpreter while building JIT
✅ **Do:** Focus on JIT, interpreter is temporary

❌ **Don't:** Support all platforms at once
✅ **Do:** Start with x86-64 on your dev machine

❌ **Don't:** Build complex optimizations first
✅ **Do:** Start with simple 1:1 bytecode → asm translation

❌ **Don't:** Skip testing
✅ **Do:** Test JIT vs interpreter on every change

❌ **Don't:** Make fib-specific optimizations
✅ **Do:** Make general bytecode → native translations

## Debugging Tips

```nim
# 1. Dump generated code as hex
proc dump_hex(code: seq[uint8]) =
  for i, b in code:
    stdout.write b.toHex(), " "
    if (i+1) mod 16 == 0: echo ""

# 2. Disassemble with objdump
writeFile("/tmp/jit.bin", code)
discard execCmd("objdump -D -b binary -m i386:x86-64 /tmp/jit.bin")

# 3. Compare with compiler output
# Write equivalent C, compile with gcc -S -O0, compare

# 4. Use godbolt.org
# See what real compilers generate for reference

# 5. Test each encoder in isolation
test "emit_add_reg_reg":
  var cg = CodeGen()
  cg.emit_add_reg_reg(RAX, RBX)
  check cg.code == [0x48'u8, 0x01'u8, 0xD8'u8]
```

## Testing Strategy

```nim
# 1. Unit tests - Each encoder
test "emit_push_imm":
  var cg = CodeGen()
  cg.emit_push_imm(42)
  check cg.code[0..1] == [0x48'u8, 0xB8'u8]

# 2. Correctness tests - JIT matches interpreter
test "JIT matches interpreter":
  for n in 0..20:
    let interp = fib_interpreted(n)
    let jit = fib_jit(n)
    check interp == jit

# 3. Performance tests - JIT is faster
test "JIT speedup":
  let interp_time = benchmark(fib_interpreted(24))
  let jit_time = benchmark(fib_jit(24))
  check jit_time < interp_time / 10  # At least 10x faster

# 4. Differential fuzzing - Random inputs
for i in 0..<1000:
  let input = random_value()
  check jit(input) == interpreted(input)
```

## Instruction Encoder Priority

**Week 1 (Core - 10 encoders):**
- emit_push_reg, emit_pop_reg
- emit_mov_reg_reg, emit_mov_reg_imm
- emit_add_reg_reg, emit_sub_reg_reg
- emit_cmp_reg_reg
- emit_jmp, emit_je
- emit_ret

**Week 2 (Arithmetic - 8 encoders):**
- emit_mul_reg_reg, emit_div_reg (complex!)
- emit_neg_reg
- emit_and_reg_reg, emit_or_reg_reg, emit_xor_reg_reg
- emit_shl_reg, emit_shr_reg

**Week 3 (Control Flow - 7 encoders):**
- emit_jne, emit_jl, emit_jle, emit_jg, emit_jge
- emit_call_rel32
- emit_test_reg_reg

**Week 4 (Memory - 5 encoders):**
- emit_mov_reg_mem, emit_mov_mem_reg
- emit_lea (useful for address calculations)
- emit_push_mem, emit_pop_mem

## Memory Management

```nim
# Executable memory allocation (POSIX)
proc allocate_executable_memory(size: int): pointer =
  let addr = mmap(
    nil, size,
    PROT_READ or PROT_WRITE,
    MAP_PRIVATE or MAP_ANONYMOUS,
    -1, 0
  )
  if addr == MAP_FAILED:
    raise newException(OutOfMemoryError, "Cannot allocate JIT memory")
  return addr

proc make_executable(addr: pointer, size: int) =
  if mprotect(addr, size, PROT_READ or PROT_EXEC) != 0:
    raise newException(OSError, "Cannot make memory executable")

# Pool management
type JitMemoryPool = object
  pages: seq[JitPage]

proc allocate_from_pool(pool: var JitMemoryPool, size: int): pointer =
  # Find page with space or allocate new one
  for page in pool.pages.mitems:
    if page.free_space >= size:
      return page.allocate(size)

  let new_page = allocate_page(4096)
  pool.pages.add(new_page)
  return new_page.allocate(size)
```

## Resources

**Learn x86-64:**
- **Compiler Explorer (godbolt.org)** - See what compilers generate
- **Intel manuals** - Official instruction reference
- **Felix Cloutier's reference** - Easier to read than Intel

**Example Code:**
- **LuaJIT source** - Clean, well-documented JIT
- **V8 source** - Industry standard (complex)
- **JavaScriptCore** - Apple's JS engine

**Tools:**
- **objdump** - Disassemble generated code
- **perf** (Linux) - Profile JIT performance
- **Instruments** (macOS) - Profile JIT performance
- **gdb** - Debug generated code

## Next Steps

1. ✅ Read [jit_design.md](./jit_design.md) for complete design
2. ✅ Implement profiling infrastructure (Week 1-2)
3. ✅ Create basic instruction encoders (Week 3-4)
4. ✅ Build simple compiler (Week 5-6)
5. ✅ Integrate with VM (Week 7-8)
6. ✅ Measure speedup (should be 10-20x)
7. ⏳ Add type specialization (Week 9-11)
8. ⏳ Add function inlining (Week 12-14)
9. ⏳ Advanced optimizations (Week 15+)

## Key Principles

**🎯 Focus on hot code:** Only 1% of code runs 99% of the time
**📊 Measure everything:** Profile before and after each change
**✅ Test correctness first:** Speed means nothing if results are wrong
**🔧 Build incrementally:** Working simple JIT → Add optimizations
**📚 Learn from others:** Study LuaJIT, V8, JavaScriptCore designs

**Remember:** Direct codegen handles all code uniformly. No special-casing for fib or other specific functions. This makes the JIT simpler, more maintainable, and more general.
