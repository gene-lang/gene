## Bytecode to HIR Conversion
##
## Converts Gene bytecode (CompilationUnit) to HIR for native code generation.
## Currently focused on typed functions like fib(n: Int) -> Int.
##
## Strategy:
## 1. Simulate bytecode execution on an abstract stack
## 2. Track which HIR register holds each stack slot
## 3. Convert each bytecode instruction to equivalent HIR operations
## 4. Handle control flow by creating basic blocks at branch targets

import std/[tables, strformat, strutils]
import ../types
import ./hir

type
  ## Tracks the abstract stack during conversion
  StackSlot = object
    reg: HirReg
    typ: HirType

  ## Conversion context
  ConversionContext = ref object
    builder: HirBuilder
    cu: CompilationUnit
    fnName: string
    paramTypes: seq[tuple[name: string, typ: HirType]]
    returnType: HirType
    
    # Abstract stack simulation
    stack: seq[StackSlot]
    
    # Map bytecode PC -> HIR block (for jump targets)
    pcToBlock: Table[int, HirBlockId]
    
    # Track which blocks we've already emitted
    emittedBlocks: Table[int, bool]
    
    # Pending blocks to process (PC values)
    pendingBlocks: seq[int]

# ==================== Type Mapping ====================

proc geneTypeToHir(typeName: string): HirType =
  ## Convert Gene type annotation to HIR type
  case typeName.toLowerAscii()
  of "int", "int64", "i64": HtI64
  of "float", "float64", "f64": HtF64
  of "bool", "boolean": HtBool
  else: HtValue  # Dynamic/unknown types use boxed Value

# ==================== Stack Operations ====================

proc push(ctx: ConversionContext, reg: HirReg, typ: HirType) =
  ctx.stack.add(StackSlot(reg: reg, typ: typ))

proc pop(ctx: ConversionContext): StackSlot =
  if ctx.stack.len == 0:
    raise newException(ValueError, "Stack underflow during HIR conversion")
  result = ctx.stack.pop()

proc peek(ctx: ConversionContext): StackSlot =
  if ctx.stack.len == 0:
    raise newException(ValueError, "Stack empty during HIR conversion")
  result = ctx.stack[^1]

# ==================== Block Management ====================

proc getOrCreateBlock(ctx: ConversionContext, pc: int, name: string): HirBlockId =
  if pc in ctx.pcToBlock:
    return ctx.pcToBlock[pc]
  let blockId = ctx.builder.newBlock(name)
  ctx.pcToBlock[pc] = blockId
  result = blockId

proc scheduleBlock(ctx: ConversionContext, pc: int) =
  if pc notin ctx.emittedBlocks:
    ctx.pendingBlocks.add(pc)

# ==================== Instruction Conversion ====================

proc convertInstruction(ctx: ConversionContext, pc: var int): bool =
  ## Convert one bytecode instruction. Returns false if block ends.
  let inst = ctx.cu.instructions[pc]
  
  case inst.kind
  of IkStart:
    # Function entry - parameters are already in registers
    discard
    
  of IkJumpIfMatchSuccess:
    # Argument matching succeeded - skip to target
    # For typed functions, we assume matching always succeeds
    let target = inst.arg1.int
    pc = target - 1  # Will be incremented at end
    
  of IkThrow:
    # Argument mismatch - shouldn't happen for typed functions
    discard
    
  of IkVarLeValue:
    # var[arg1] <= Data[pc+1].arg0
    let varIdx = inst.arg1
    let dataInst = ctx.cu.instructions[pc + 1]
    let constVal = dataInst.arg0.to_int()
    
    # Get parameter register (params are registers 0..n-1)
    let paramReg = newHirReg(varIdx)
    let constReg = ctx.builder.emitConstI64(constVal)
    let resultReg = ctx.builder.emitLeI64(paramReg, constReg)
    ctx.push(resultReg, HtBool)
    pc += 1  # Skip Data instruction
    
  of IkVarSubValue:
    # var[arg1] - Data[pc+1].arg0
    let varIdx = inst.arg1
    let dataInst = ctx.cu.instructions[pc + 1]
    let constVal = dataInst.arg0.to_int()
    
    let paramReg = newHirReg(varIdx)
    let constReg = ctx.builder.emitConstI64(constVal)
    let resultReg = ctx.builder.emitSubI64(paramReg, constReg)
    ctx.push(resultReg, HtI64)
    pc += 1  # Skip Data instruction
    
  of IkData:
    # Data instruction - should be consumed by previous instruction
    discard
    
  of IkJumpIfFalse:
    # Conditional branch
    let target = inst.arg1.int
    let cond = ctx.pop()
    
    # Create blocks for then and else branches
    let thenBlock = ctx.getOrCreateBlock(pc + 1, fmt"then_{pc}")
    let elseBlock = ctx.getOrCreateBlock(target, fmt"else_{target}")
    
    ctx.builder.emitBr(cond.reg, thenBlock, elseBlock)
    
    # Schedule both branches for processing
    ctx.scheduleBlock(pc + 1)
    ctx.scheduleBlock(target)
    return false  # Block ends
    
  of IkVarResolve:
    # Push variable value onto stack
    let varIdx = inst.arg1
    let paramReg = newHirReg(varIdx)
    ctx.push(paramReg, HtI64)  # Assume Int for now
    
  of IkJump:
    # Unconditional jump
    let target = inst.arg1.int
    let targetBlock = ctx.getOrCreateBlock(target, fmt"block_{target}")
    ctx.builder.emitJump(targetBlock)
    ctx.scheduleBlock(target)
    return false  # Block ends
    
  of IkResolveSymbol:
    # Push function reference - for recursive calls, we track the name
    # The actual call happens in UnifiedCall1
    # We just push a placeholder here
    ctx.push(newHirReg(-1), HtValue)  # Placeholder
    
  of IkUnifiedCall1:
    # Call with 1 argument
    # Stack: [fn, arg] -> [result]
    let arg = ctx.pop()
    discard ctx.pop()  # Function reference (we use fnName instead)
    
    let resultReg = ctx.builder.emitCall(ctx.fnName, @[arg.reg], ctx.returnType)
    ctx.push(resultReg, ctx.returnType)
    
  of IkAdd:
    # Add top two stack values
    let right = ctx.pop()
    let left = ctx.pop()
    let resultReg = ctx.builder.emitAddI64(left.reg, right.reg)
    ctx.push(resultReg, HtI64)

  of IkPop:
    # Pop and discard top of stack
    if ctx.stack.len > 0:
      discard ctx.pop()

  of IkPushValue:
    # Push a literal value onto stack (used in else branch for n)
    let val = inst.arg0
    if val.kind == VkInt:
      let constReg = ctx.builder.emitConstI64(val.to_int())
      ctx.push(constReg, HtI64)
    else:
      # For other values, push as-is (placeholder)
      ctx.push(newHirReg(-1), HtValue)

  of IkScopeEnd:
    # Scope cleanup - no HIR equivalent needed
    discard

  of IkEnd:
    # Function end - return top of stack
    if ctx.stack.len > 0:
      let retVal = ctx.pop()
      ctx.builder.emitRet(retVal.reg)
    return false  # Block ends

  else:
    # Unsupported instruction
    raise newException(ValueError, fmt"Unsupported bytecode instruction: {inst.kind}")

  result = true  # Continue processing

# ==================== Block Processing ====================

proc processBlock(ctx: ConversionContext, startPc: int) =
  ## Process a basic block starting at the given PC
  if startPc in ctx.emittedBlocks:
    return
  ctx.emittedBlocks[startPc] = true

  # Get or create the block
  let blockId = ctx.getOrCreateBlock(startPc, fmt"block_{startPc}")
  ctx.builder.setCurrentBlock(blockId)

  var pc = startPc
  while pc < ctx.cu.instructions.len:
    if not ctx.convertInstruction(pc):
      break  # Block ended (branch, jump, or return)
    pc += 1

# ==================== Main Conversion ====================

proc extractFunctionInfo(cu: CompilationUnit): tuple[name: string, params: seq[tuple[name: string, typ: HirType]], retType: HirType] =
  ## Extract function name and parameter types from CompilationUnit
  result.name = "unknown"
  result.params = @[]
  result.retType = HtI64  # Default to Int

  if cu.matcher != nil:
    for child in cu.matcher.children:
      let paramName = cast[Value](child.name_key).str()
      let paramType = if child.type_name.len > 0:
        geneTypeToHir(child.type_name)
      else:
        HtValue
      result.params.add((name: paramName, typ: paramType))

proc bytecodeToHir*(cu: CompilationUnit, fnName: string = "fn"): HirFunction =
  ## Convert a CompilationUnit to HIR
  ##
  ## Parameters:
  ##   cu: The compiled bytecode
  ##   fnName: Function name (for recursive calls)
  ##
  ## Returns:
  ##   HirFunction ready for native code generation

  let info = extractFunctionInfo(cu)
  let actualName = if fnName != "fn": fnName else: info.name

  # Determine return type (default to Int for now)
  let returnType = info.retType

  # Create builder
  let builder = newHirBuilder(actualName, returnType)

  # Add parameters
  for param in info.params:
    discard builder.addParam(param.name, param.typ)

  # Create conversion context
  let ctx = ConversionContext(
    builder: builder,
    cu: cu,
    fnName: actualName,
    paramTypes: info.params,
    returnType: returnType,
    stack: @[],
    pcToBlock: initTable[int, HirBlockId](),
    emittedBlocks: initTable[int, bool](),
    pendingBlocks: @[]
  )

  # Create entry block and start processing
  let entryBlock = builder.newBlock("entry")
  ctx.pcToBlock[0] = entryBlock
  ctx.pendingBlocks.add(0)

  # Process all reachable blocks
  while ctx.pendingBlocks.len > 0:
    let pc = ctx.pendingBlocks.pop()
    ctx.processBlock(pc)

  result = builder.finalize()
  result.isNativeEligible = true  # We only convert typed functions

# ==================== Eligibility Check ====================

proc isNativeEligible*(cu: CompilationUnit): bool =
  ## Check if a CompilationUnit can be converted to native code
  ## Currently requires:
  ## - All parameters have type annotations
  ## - Types are primitive (Int, Float, Bool)

  if cu.matcher == nil:
    return false

  if not cu.matcher.has_type_annotations:
    return false

  for child in cu.matcher.children:
    if child.type_name.len == 0:
      return false
    let hirType = geneTypeToHir(child.type_name)
    if hirType == HtValue:
      return false  # Non-primitive type

  return true

