import system

import ../memory
import ./encoders

type
  ThunkBuildResult* = object
    code*: pointer
    size*: int

proc build_jmp_thunk*(target: pointer): ThunkBuildResult =
  ## Build a tiny ARM64 thunk that jumps to `target`.
  ## Layout: mov x16, imm64; br x16
  var code: seq[uint32] = @[]
  
  # Load 64-bit immediate into x16 using MOVZ+MOVK sequence
  code.emit_mov_reg_imm64(16, cast[uint64](target))
  
  # BR X16 - unconditional branch to address in X16
  code.emit(0xD61F0200'u32)  # br x16
  
  let byte_size = code.len * sizeof(uint32)
  let mem = allocate_executable_memory(byte_size)
  copyMem(mem, code[0].unsafeAddr, byte_size)
  make_executable(mem, byte_size)
  ThunkBuildResult(code: mem, size: byte_size)

