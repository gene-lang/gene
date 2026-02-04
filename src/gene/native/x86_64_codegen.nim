## x86-64 Code Generator for Gene HIR
##
## Generates native x86-64 machine code from HIR.
## Uses System V AMD64 ABI (Linux/macOS calling convention).
##
## Register allocation strategy (simple, no spilling for now):
##   - Parameters: rdi, rsi, rdx, rcx, r8, r9 (first 6 args)
##   - Return value: rax
##   - Callee-saved: rbx, rbp, r12-r15
##   - Caller-saved: rax, rcx, rdx, rsi, rdi, r8-r11
##   - HIR registers map to stack slots or physical registers
##
## For simplicity, we use a stack-based approach:
##   - All HIR registers are stored on the stack
##   - Operations load from stack, compute, store to stack
##   - This is inefficient but correct; optimization comes later

import std/[tables, strformat]
import ./hir

type
  ## x86-64 physical registers
  X86Reg* = enum
    RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI,
    R8, R9, R10, R11, R12, R13, R14, R15

  ## Code buffer for emitting bytes
  CodeBuffer* = ref object
    code*: seq[byte]
    labels*: Table[HirBlockId, int]      # Block -> code offset
    fixups*: seq[tuple[offset: int, target: HirBlockId, isRel32: bool]]
    
  ## Codegen context
  CodegenContext* = ref object
    buf*: CodeBuffer
    fn*: HirFunction
    stackSize*: int32                    # Total stack frame size
    regOffsets*: Table[int32, int32]     # HIR reg -> stack offset from RBP
    fnEntryOffset*: int                  # Offset of function entry point (for recursive calls)
    recursiveCallFixups*: seq[int]       # Offsets that need to be patched for recursive calls

# ==================== Code Buffer Operations ====================

proc newCodeBuffer*(): CodeBuffer =
  CodeBuffer(
    code: @[],
    labels: initTable[HirBlockId, int](),
    fixups: @[]
  )

proc emit*(buf: CodeBuffer, b: byte) {.inline.} =
  buf.code.add(b)

proc emit*(buf: CodeBuffer, bytes: openArray[byte]) {.inline.} =
  for b in bytes:
    buf.code.add(b)

proc emitI32*(buf: CodeBuffer, val: int32) =
  buf.emit(byte(val and 0xFF))
  buf.emit(byte((val shr 8) and 0xFF))
  buf.emit(byte((val shr 16) and 0xFF))
  buf.emit(byte((val shr 24) and 0xFF))

proc emitI64*(buf: CodeBuffer, val: int64) =
  buf.emit(byte(val and 0xFF))
  buf.emit(byte((val shr 8) and 0xFF))
  buf.emit(byte((val shr 16) and 0xFF))
  buf.emit(byte((val shr 24) and 0xFF))
  buf.emit(byte((val shr 32) and 0xFF))
  buf.emit(byte((val shr 40) and 0xFF))
  buf.emit(byte((val shr 48) and 0xFF))
  buf.emit(byte((val shr 56) and 0xFF))

proc currentOffset*(buf: CodeBuffer): int {.inline.} =
  buf.code.len

proc markLabel*(buf: CodeBuffer, blockId: HirBlockId) =
  buf.labels[blockId] = buf.currentOffset()

proc addFixup*(buf: CodeBuffer, target: HirBlockId, isRel32: bool = true) =
  buf.fixups.add((offset: buf.currentOffset(), target: target, isRel32: isRel32))

proc resolveFixups*(buf: CodeBuffer) =
  for fixup in buf.fixups:
    if fixup.target notin buf.labels:
      raise newException(ValueError, fmt"Unresolved label: {fixup.target}")
    let targetOffset = buf.labels[fixup.target]
    if fixup.isRel32:
      # rel32 is relative to the end of the instruction (after the 4-byte offset)
      let rel = int32(targetOffset - (fixup.offset + 4))
      buf.code[fixup.offset] = byte(rel and 0xFF)
      buf.code[fixup.offset + 1] = byte((rel shr 8) and 0xFF)
      buf.code[fixup.offset + 2] = byte((rel shr 16) and 0xFF)
      buf.code[fixup.offset + 3] = byte((rel shr 24) and 0xFF)

# ==================== x86-64 Instruction Encoding ====================

# REX prefix for 64-bit operations
const REX_W: byte = 0x48  # 64-bit operand size
const REX_R: byte = 0x44  # Extension of ModR/M reg field
const REX_X: byte = 0x42  # Extension of SIB index field  
const REX_B: byte = 0x41  # Extension of ModR/M r/m or SIB base

proc regCode(r: X86Reg): byte {.inline.} =
  byte(ord(r) and 0x07)

proc needsRex(r: X86Reg): bool {.inline.} =
  ord(r) >= 8

proc rexFor(r: X86Reg): byte {.inline.} =
  if needsRex(r): REX_B else: 0

proc rexForReg(reg, rm: X86Reg): byte {.inline.} =
  var rex: byte = 0
  if needsRex(reg): rex = rex or REX_R
  if needsRex(rm): rex = rex or REX_B
  rex

# ModR/M byte: mod(2) | reg(3) | r/m(3)
proc modRM(mode: byte, reg, rm: X86Reg): byte {.inline.} =
  (mode shl 6) or (regCode(reg) shl 3) or regCode(rm)

# ==================== Common Instructions ====================

proc emitPush*(buf: CodeBuffer, reg: X86Reg) =
  if needsRex(reg):
    buf.emit(REX_B)
  buf.emit(0x50 + regCode(reg))

proc emitPop*(buf: CodeBuffer, reg: X86Reg) =
  if needsRex(reg):
    buf.emit(REX_B)
  buf.emit(0x58 + regCode(reg))

proc emitMovRegImm64*(buf: CodeBuffer, reg: X86Reg, imm: int64) =
  ## mov reg, imm64 (REX.W + B8+rd)
  buf.emit(REX_W or rexFor(reg))
  buf.emit(0xB8 + regCode(reg))
  buf.emitI64(imm)

proc emitMovRegReg*(buf: CodeBuffer, dst, src: X86Reg) =
  ## mov dst, src
  buf.emit(REX_W or rexForReg(src, dst))
  buf.emit(0x89)
  buf.emit(modRM(0b11, src, dst))

proc emitMovRegMem*(buf: CodeBuffer, dst: X86Reg, base: X86Reg, offset: int32) =
  ## mov dst, [base + offset]
  buf.emit(REX_W or rexForReg(dst, base))
  buf.emit(0x8B)
  if offset == 0 and base != RBP and base != R13:
    buf.emit(modRM(0b00, dst, base))
  elif offset >= -128 and offset <= 127:
    buf.emit(modRM(0b01, dst, base))
    buf.emit(byte(offset and 0xFF))
  else:
    buf.emit(modRM(0b10, dst, base))
    buf.emitI32(offset)

proc emitMovMemReg*(buf: CodeBuffer, base: X86Reg, offset: int32, src: X86Reg) =
  ## mov [base + offset], src
  buf.emit(REX_W or rexForReg(src, base))
  buf.emit(0x89)
  if offset == 0 and base != RBP and base != R13:
    buf.emit(modRM(0b00, src, base))
  elif offset >= -128 and offset <= 127:
    buf.emit(modRM(0b01, src, base))
    buf.emit(byte(offset and 0xFF))
  else:
    buf.emit(modRM(0b10, src, base))
    buf.emitI32(offset)

proc emitAddRegReg*(buf: CodeBuffer, dst, src: X86Reg) =
  ## add dst, src
  buf.emit(REX_W or rexForReg(src, dst))
  buf.emit(0x01)
  buf.emit(modRM(0b11, src, dst))

proc emitSubRegReg*(buf: CodeBuffer, dst, src: X86Reg) =
  ## sub dst, src
  buf.emit(REX_W or rexForReg(src, dst))
  buf.emit(0x29)
  buf.emit(modRM(0b11, src, dst))

proc emitCmpRegReg*(buf: CodeBuffer, left, right: X86Reg) =
  ## cmp left, right
  buf.emit(REX_W or rexForReg(right, left))
  buf.emit(0x39)
  buf.emit(modRM(0b11, right, left))

proc emitSetLE*(buf: CodeBuffer, dst: X86Reg) =
  ## setle dst (set byte if less or equal)
  if needsRex(dst):
    buf.emit(0x40 or rexFor(dst))
  buf.emit(0x0F)
  buf.emit(0x9E)
  buf.emit(modRM(0b11, RAX, dst))  # RAX is placeholder for opcode extension

proc emitMovzxRegByte*(buf: CodeBuffer, dst: X86Reg) =
  ## movzx dst, dl (zero-extend byte to 64-bit)
  buf.emit(REX_W or rexForReg(dst, dst))
  buf.emit(0x0F)
  buf.emit(0xB6)
  buf.emit(modRM(0b11, dst, dst))

proc emitJmp*(buf: CodeBuffer, target: HirBlockId) =
  ## jmp rel32 (with fixup)
  buf.emit(0xE9)
  buf.addFixup(target)
  buf.emitI32(0)  # Placeholder for rel32

proc emitJe*(buf: CodeBuffer, target: HirBlockId) =
  ## je rel32 (jump if equal/zero)
  buf.emit(0x0F)
  buf.emit(0x84)
  buf.addFixup(target)
  buf.emitI32(0)

proc emitJne*(buf: CodeBuffer, target: HirBlockId) =
  ## jne rel32 (jump if not equal/not zero)
  buf.emit(0x0F)
  buf.emit(0x85)
  buf.addFixup(target)
  buf.emitI32(0)

proc emitTestRegReg*(buf: CodeBuffer, reg1, reg2: X86Reg) =
  ## test reg1, reg2
  buf.emit(REX_W or rexForReg(reg1, reg2))
  buf.emit(0x85)
  buf.emit(modRM(0b11, reg1, reg2))

proc emitRet*(buf: CodeBuffer) =
  buf.emit(0xC3)

proc emitCall*(buf: CodeBuffer, target: HirBlockId) =
  ## call rel32 (with fixup) - for internal calls
  buf.emit(0xE8)
  buf.addFixup(target)
  buf.emitI32(0)

proc emitCallReg*(buf: CodeBuffer, reg: X86Reg) =
  ## call reg (indirect call)
  if needsRex(reg):
    buf.emit(REX_B)
  buf.emit(0xFF)
  buf.emit(modRM(0b11, RDX, reg))  # /2 opcode extension

proc emitSubRspImm*(buf: CodeBuffer, imm: int32) =
  ## sub rsp, imm32
  # 48 81 ec imm32 = sub rsp, imm32
  # ModR/M: 11 101 100 = 0xEC (mod=11, reg=/5, r/m=RSP)
  buf.emit(REX_W)
  buf.emit(0x81)
  buf.emit(0xEC)  # ModR/M for /5, RSP
  buf.emitI32(imm)

proc emitAddRspImm*(buf: CodeBuffer, imm: int32) =
  ## add rsp, imm32
  # 48 81 c4 imm32 = add rsp, imm32
  # ModR/M: 11 000 100 = 0xC4 (mod=11, reg=/0, r/m=RSP)
  buf.emit(REX_W)
  buf.emit(0x81)
  buf.emit(0xC4)  # ModR/M for /0, RSP
  buf.emitI32(imm)

# ==================== Codegen Context ====================

proc newCodegenContext*(fn: HirFunction): CodegenContext =
  result = CodegenContext(
    buf: newCodeBuffer(),
    fn: fn,
    regOffsets: initTable[int32, int32](),
    fnEntryOffset: 0,
    recursiveCallFixups: @[]
  )

  # Calculate stack layout: each HIR register gets 8 bytes
  # Stack grows downward, so reg 0 is at [rbp - 8], reg 1 at [rbp - 16], etc.
  for i in 0..<fn.regCount:
    result.regOffsets[i] = -8 * (i + 1)

  # Align stack to 16 bytes
  result.stackSize = ((fn.regCount * 8 + 15) div 16) * 16
  if result.stackSize < 16:
    result.stackSize = 16

proc regOffset*(ctx: CodegenContext, reg: HirReg): int32 =
  ctx.regOffsets[int32(reg)]

proc loadReg*(ctx: CodegenContext, dst: X86Reg, hirReg: HirReg) =
  ## Load HIR register from stack into x86 register
  ctx.buf.emitMovRegMem(dst, RBP, ctx.regOffset(hirReg))

proc storeReg*(ctx: CodegenContext, hirReg: HirReg, src: X86Reg) =
  ## Store x86 register to HIR register on stack
  ctx.buf.emitMovMemReg(RBP, ctx.regOffset(hirReg), src)

# ==================== HIR Operation Codegen ====================

proc genOp*(ctx: CodegenContext, op: HirOp)

proc genConstI64*(ctx: CodegenContext, op: HirOp) =
  ctx.buf.emitMovRegImm64(RAX, op.constI64)
  ctx.storeReg(op.dest, RAX)

proc genAddI64*(ctx: CodegenContext, op: HirOp) =
  ctx.loadReg(RAX, op.binLeft)
  ctx.loadReg(RCX, op.binRight)
  ctx.buf.emitAddRegReg(RAX, RCX)
  ctx.storeReg(op.dest, RAX)

proc genSubI64*(ctx: CodegenContext, op: HirOp) =
  ctx.loadReg(RAX, op.binLeft)
  ctx.loadReg(RCX, op.binRight)
  ctx.buf.emitSubRegReg(RAX, RCX)
  ctx.storeReg(op.dest, RAX)

proc genLeI64*(ctx: CodegenContext, op: HirOp) =
  ctx.loadReg(RAX, op.binLeft)
  ctx.loadReg(RCX, op.binRight)
  ctx.buf.emitCmpRegReg(RAX, RCX)
  ctx.buf.emitSetLE(RAX)
  ctx.buf.emitMovzxRegByte(RAX)
  ctx.storeReg(op.dest, RAX)

proc genBr*(ctx: CodegenContext, op: HirOp) =
  # Load condition and test
  ctx.loadReg(RAX, op.brCond)
  ctx.buf.emitTestRegReg(RAX, RAX)
  # Jump to else if zero (condition false)
  ctx.buf.emitJe(op.brElse)
  # Fall through or jump to then
  ctx.buf.emitJmp(op.brThen)

proc genJump*(ctx: CodegenContext, op: HirOp) =
  ctx.buf.emitJmp(op.jumpTarget)

proc genRet*(ctx: CodegenContext, op: HirOp) =
  ctx.loadReg(RAX, op.retValue)
  # Epilogue
  ctx.buf.emitMovRegReg(RSP, RBP)
  ctx.buf.emitPop(RBP)
  ctx.buf.emitRet()

proc genCall*(ctx: CodegenContext, op: HirOp) =
  # Load arguments into System V ABI registers
  const argRegs = [RDI, RSI, RDX, RCX, R8, R9]
  if op.callArgs.len > argRegs.len:
    raise newException(ValueError, "Too many arguments for native call: " & $op.callArgs.len)
  for i in 0..<op.callArgs.len:
    ctx.loadReg(argRegs[i], op.callArgs[i])

  # Check if this is a recursive call (calling ourselves)
  if op.callTarget == ctx.fn.name:
    # Emit call rel32, track fixup location
    ctx.buf.emit(0xE8)
    ctx.recursiveCallFixups.add(ctx.buf.currentOffset())
    ctx.buf.emitI32(0)  # Placeholder - will be patched
  else:
    raise newException(ValueError, "External native calls not supported: " & op.callTarget)

  # Store result
  ctx.storeReg(op.dest, RAX)

proc genOp*(ctx: CodegenContext, op: HirOp) =
  case op.kind
  of HokConstI64: ctx.genConstI64(op)
  of HokAddI64: ctx.genAddI64(op)
  of HokSubI64: ctx.genSubI64(op)
  of HokLeI64: ctx.genLeI64(op)
  of HokBr: ctx.genBr(op)
  of HokJump: ctx.genJump(op)
  of HokRet: ctx.genRet(op)
  of HokCall: ctx.genCall(op)
  else:
    raise newException(ValueError, "Unsupported HIR op: " & $op.kind)

# ==================== Function Generation ====================

proc genPrologue*(ctx: CodegenContext) =
  ## Generate function prologue
  ctx.buf.emitPush(RBP)
  ctx.buf.emitMovRegReg(RBP, RSP)
  ctx.buf.emitSubRspImm(ctx.stackSize)

  # Store parameters (System V ABI) to HIR register slots
  const argRegs = [RDI, RSI, RDX, RCX, R8, R9]
  let count = min(ctx.fn.params.len, argRegs.len)
  for i in 0..<count:
    ctx.buf.emitMovMemReg(RBP, ctx.regOffset(newHirReg(i.int32)), argRegs[i])

proc genBlock*(ctx: CodegenContext, blk: HirBlock) =
  ctx.buf.markLabel(blk.id)
  for op in blk.ops:
    ctx.genOp(op)

proc resolveRecursiveCallFixups*(ctx: CodegenContext) =
  ## Patch all recursive calls to point to function entry
  for offset in ctx.recursiveCallFixups:
    # rel32 is relative to the end of the call instruction (offset + 4)
    let rel = int32(ctx.fnEntryOffset - (offset + 4))
    ctx.buf.code[offset] = byte(rel and 0xFF)
    ctx.buf.code[offset + 1] = byte((rel shr 8) and 0xFF)
    ctx.buf.code[offset + 2] = byte((rel shr 16) and 0xFF)
    ctx.buf.code[offset + 3] = byte((rel shr 24) and 0xFF)

proc generateCode*(fn: HirFunction): seq[byte] =
  ## Generate x86-64 machine code for an HIR function
  let ctx = newCodegenContext(fn)

  # Record function entry point (at the very start)
  ctx.fnEntryOffset = 0

  # Generate prologue
  ctx.genPrologue()

  # Generate all blocks
  for blk in fn.blocks:
    ctx.genBlock(blk)

  # Resolve jump fixups (for branches)
  ctx.buf.resolveFixups()

  # Resolve recursive call fixups
  ctx.resolveRecursiveCallFixups()

  result = ctx.buf.code

proc disassemble*(code: seq[byte]): string =
  ## Simple hex dump of generated code
  result = "Generated code (" & $code.len & " bytes):\n"
  for i, b in code:
    if i mod 16 == 0:
      if i > 0: result &= "\n"
      result &= fmt"{i:04x}: "
    result &= fmt"{b:02x} "
  result &= "\n"
