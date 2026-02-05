## Test bytecode to HIR conversion and x86-64 code generation
##
## Compiles the fib function from Gene source, converts bytecode to HIR,
## then generates x86-64 machine code.

import ../src/gene/types
import ../src/gene/compiler
import ../src/gene/native/hir
import ../src/gene/native/bytecode_to_hir
import ../src/gene/vm
when defined(amd64):
  import ../src/gene/native/x86_64_codegen as codegen
elif defined(arm64) or defined(aarch64):
  import ../src/gene/native/arm64_codegen as codegen
else:
  import ../src/gene/native/x86_64_codegen as codegen
import std/[strformat, tables]

when defined(posix):
  import std/posix

const FIB_SOURCE = """
(fn fib [n: Int] -> Int
  (if (<= n 1)
    n
  else
    (+ (fib (- n 1)) (fib (- n 2)))))
"""

proc printBytecode(cu: CompilationUnit, name: string) =
  echo fmt"=== Bytecode for {name} ==="
  echo fmt"Instructions: {cu.instructions.len}"
  if cu.matcher != nil:
    echo fmt"Has type annotations: {cu.matcher.has_type_annotations}"
    for child in cu.matcher.children:
      let paramName = cast[Value](child.name_key).str()
      echo fmt"  Param: {paramName}, type: {child.type_name}"
  echo ""
  echo "Labels: "
  for label, pc in cu.labels.pairs:
    echo fmt"  L{label} -> PC {pc}"
  echo ""
  for i, inst in cu.instructions:
    let label = if inst.label != 0: fmt"L{inst.label}: " else: "     "
    var extra = ""
    if inst.kind in {IkJump, IkJumpIfFalse}:
      extra = fmt" -> PC {inst.arg0.int64}"
    elif inst.kind == IkJumpIfMatchSuccess:
      extra = fmt" -> PC {inst.arg1}"
    elif inst.kind in {IkVarResolve, IkVarLeValue, IkVarSubValue}:
      extra = fmt" var[{inst.arg0.int64}]"
    elif inst.kind == IkData:
      extra = fmt" = {inst.arg0}"
    elif inst.kind == IkPushValue:
      extra = fmt" = {inst.arg0}"
    elif inst.kind == IkResolveSymbol:
      extra = fmt" '{inst.arg0.str()}'"
    echo fmt"{i:3}: {label}{inst.kind}{extra}"

proc main() =
  echo "=== Compiling fib function ==="
  echo ""
  
  # Compile the module
  let moduleCu = parse_and_compile(FIB_SOURCE, eager_functions = true)
  
  echo fmt"Module has {moduleCu.instructions.len} instructions"
  echo ""
  
  # Find the IkFunction instruction
  var functionDefInfo: FunctionDefInfo = nil
  for inst in moduleCu.instructions:
    if inst.kind == IkFunction:
      functionDefInfo = inst.arg0.to_function_def_info()
      break
  
  if functionDefInfo.isNil:
    echo "ERROR: No function found in compiled module"
    return
  
  # Extract the function's CompilationUnit
  let bodyValue = functionDefInfo.compiled_body
  if bodyValue == NIL:
    echo "ERROR: Function body not compiled"
    return
  
  # Get the CompilationUnit from the ref value
  let bodyRef = bodyValue.ref
  if bodyRef.kind != VkCompiledUnit:
    echo fmt"ERROR: Expected VkCompiledUnit, got {bodyRef.kind}"
    return
  
  let funcCu = bodyRef.cu
  
  echo "Found function bytecode!"
  echo ""
  printBytecode(funcCu, "fib")
  
  echo ""
  echo "=== Converting to HIR ==="
  echo ""
  
  # Check eligibility
  let eligible = isNativeEligible(funcCu, "fib")
  echo fmt"Native eligible: {eligible}"
  echo ""
  
  # Convert to HIR
  let hirFunc = bytecodeToHir(funcCu, "fib")
  
  echo "=== HIR Output ==="
  echo ""
  echo $hirFunc

  echo ""
  echo "=== Generating Native Code ==="
  echo ""

  # Generate machine code
  let machineCode = codegen.generateCode(hirFunc)

  # Print disassembly
  echo codegen.disassemble(machineCode)

  echo ""
  echo "=== Testing Native Code Execution ==="
  echo ""

  when defined(posix):
    # MAP_ANONYMOUS is 0x1000 on macOS, 0x20 on Linux
    const MAP_ANON_FLAG = when defined(macosx): 0x1000.cint else: 0x20.cint
    # MAP_JIT is required on macOS for executable memory (0x800)
    const MAP_JIT_FLAG = when defined(macosx): 0x800.cint else: 0.cint

    when defined(macosx):
      proc pthread_jit_write_protect_np(enable: cint) {.importc.}
    proc clear_cache(start, `end`: ptr char) {.importc: "__builtin___clear_cache".}

    type FibFunc = proc(ctx: ptr NativeContext, n: int64): int64 {.cdecl.}

    let codeSize = machineCode.len
    let mem = mmap(nil, codeSize.cint,
                   PROT_READ or PROT_WRITE or PROT_EXEC,
                   MAP_PRIVATE or MAP_ANON_FLAG or MAP_JIT_FLAG,
                   -1.cint, 0.Off)

    if mem == MAP_FAILED:
      echo "ERROR: mmap failed"
    else:
      when defined(macosx):
        pthread_jit_write_protect_np(0)
      # Copy code to executable memory
      copyMem(mem, machineCode[0].unsafeAddr, codeSize)
      when defined(macosx):
        pthread_jit_write_protect_np(1)

      clear_cache(cast[ptr char](mem), cast[ptr char](cast[uint64](mem) + uint64(codeSize)))

      # Cast to function pointer and call
      let fib = cast[FibFunc](mem)
      var vm: VirtualMachine
      var ctx = NativeContext(
        vm: addr vm,
        trampoline: cast[pointer](native_trampoline),
        descriptors: nil,
        descriptor_count: 0
      )

      echo "Testing fib function:"
      for n in 0..10:
        let result = fib(addr ctx, n.int64)
        echo fmt"  fib({n}) = {result}"

      # Clean up
      discard munmap(mem, codeSize.cint)
  else:
    echo "Execution test only supported on POSIX systems"

  echo ""
  echo "=== Code Generation Complete ==="

when isMainModule:
  main()
