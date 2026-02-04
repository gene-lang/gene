## Test bytecode to HIR conversion
##
## Compiles the fib function from Gene source, then converts bytecode to HIR.

import ../src/gene/types
import ../src/gene/compiler
import ../src/gene/native/hir
import ../src/gene/native/bytecode_to_hir
import std/strformat

const FIB_SOURCE = """
(fn fib [n: Int] -> Int
  (if (<= n 1)
    n
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
  for i, inst in cu.instructions:
    let label = if inst.label != 0: fmt"L{inst.label}: " else: "     "
    echo fmt"{i:3}: {label}{inst.kind}"

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
  let eligible = isNativeEligible(funcCu)
  echo fmt"Native eligible: {eligible}"
  echo ""
  
  # Convert to HIR
  let hirFunc = bytecodeToHir(funcCu, "fib")
  
  echo "=== HIR Output ==="
  echo ""
  echo $hirFunc
  
  echo ""
  echo "=== Comparison Complete ==="

when isMainModule:
  main()

