{.used.}

## Minimal x86-64 byte emitters used by the baseline JIT.

proc emit*(code: var seq[uint8], bytes: openArray[uint8]) {.inline.} =
  for b in bytes:
    code.add(b)

proc emit_mov_rax_imm64*(code: var seq[uint8], imm: uint64) =
  ## mov rax, imm64
  code.emit([0x48'u8, 0xB8'u8])
  code.emit(cast[array[8, uint8]](imm))

proc emit_mov_rbx_imm64*(code: var seq[uint8], imm: uint64) =
  ## mov rbx, imm64
  code.emit([0x48'u8, 0xBB'u8])
  code.emit(cast[array[8, uint8]](imm))

proc emit_mov_rcx_imm64*(code: var seq[uint8], imm: uint64) =
  ## mov rcx, imm64
  code.emit([0x48'u8, 0xB9'u8])
  code.emit(cast[array[8, uint8]](imm))

proc emit_mov_rsi_imm64*(code: var seq[uint8], imm: uint64) =
  ## mov rsi, imm64
  code.emit([0x48'u8, 0xBE'u8])
  code.emit(cast[array[8, uint8]](imm))

proc emit_mov_reg_imm32*(code: var seq[uint8], reg_opcode: uint8, imm: int32) =
  ## mov r/m64, imm32 with rm encoded in low 3 bits (ModR/M = 0xC0 + reg)
  code.emit([0x48'u8, 0xC7'u8, (0xC0'u8 or reg_opcode)])
  code.emit(cast[array[4, uint8]](imm))

proc emit_add_rax_imm32*(code: var seq[uint8], imm: int32) =
  ## add rax, imm32
  code.emit([0x48'u8, 0x05'u8])
  code.emit(cast[array[4, uint8]](imm))

proc emit_sub_rax_imm32*(code: var seq[uint8], imm: int32) =
  ## sub rax, imm32
  code.emit([0x48'u8, 0x2D'u8])
  code.emit(cast[array[4, uint8]](imm))

proc emit_cmp_rax_imm32*(code: var seq[uint8], imm: int32) =
  ## cmp rax, imm32
  code.emit([0x48'u8, 0x3D'u8])
  code.emit(cast[array[4, uint8]](imm))

proc emit_push_rax*(code: var seq[uint8]) =
  code.emit([0x50'u8])

proc emit_push_rbx*(code: var seq[uint8]) =
  code.emit([0x53'u8])

proc emit_pop_rbx*(code: var seq[uint8]) =
  code.emit([0x5B'u8])

proc emit_pop_rax*(code: var seq[uint8]) =
  code.emit([0x58'u8])

proc emit_mov_rbx_rax*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x89'u8, 0xC3'u8]) # mov rbx, rax

proc emit_mov_rax_rbx*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x89'u8, 0xD8'u8]) # mov rax, rbx

proc emit_mov_rsi_rax*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x89'u8, 0xC6'u8]) # mov rsi, rax

proc emit_add_rax_rbx*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x01'u8, 0xD8'u8]) # add rax, rbx

proc emit_sub_rax_rbx*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x29'u8, 0xD8'u8]) # sub rax, rbx

proc emit_imul_rax_rbx*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x0F'u8, 0xAF'u8, 0xC3'u8]) # imul rax, rbx

proc emit_neg_rax*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0xF7'u8, 0xD8'u8]) # neg rax

proc emit_cmp_rax_rbx*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x39'u8, 0xD8'u8]) # cmp rax, rbx

proc emit_and_rbx_rcx*(code: var seq[uint8]) =
  ## and rbx, rcx
  code.emit([0x48'u8, 0x21'u8, 0xD9'u8])

proc emit_setcc_al*(code: var seq[uint8], cc: uint8) =
  ## setcc al with cc in low 3 bits (e.g. 0x94=sete, 0x9C=setl, etc.)
  code.emit([0x0F'u8, cc])

proc emit_movzx_rax_al*(code: var seq[uint8]) =
  code.emit([0x0F'u8, 0xB6'u8, 0xC0'u8]) # movzx eax, al (zero-extend)

proc emit_call_rax*(code: var seq[uint8]) =
  code.emit([0xFF'u8, 0xD0'u8])

proc emit_ret*(code: var seq[uint8]) =
  code.emit([0xC3'u8])

proc emit_shl_rax_imm8*(code: var seq[uint8], imm: uint8) =
  code.emit([0x48'u8, 0xC1'u8, 0xE0'u8, imm]) # shl rax, imm8

proc emit_shl_rbx_imm8*(code: var seq[uint8], imm: uint8) =
  code.emit([0x48'u8, 0xC1'u8, 0xE3'u8, imm]) # shl rbx, imm8

proc emit_sar_rax_imm8*(code: var seq[uint8], imm: uint8) =
  code.emit([0x48'u8, 0xC1'u8, 0xF8'u8, imm]) # sar rax, imm8

proc emit_sar_rbx_imm8*(code: var seq[uint8], imm: uint8) =
  code.emit([0x48'u8, 0xC1'u8, 0xFB'u8, imm]) # sar rbx, imm8

proc emit_or_rax_rbx*(code: var seq[uint8]) =
  code.emit([0x48'u8, 0x09'u8, 0xD8'u8]) # or rax, rbx

proc emit_jmp_rel32*(code: var seq[uint8], rel: int32) =
  code.emit([0xE9'u8])
  code.emit(cast[array[4, uint8]](rel))

proc emit_je_rel32*(code: var seq[uint8], rel: int32) =
  code.emit([0x0F'u8, 0x84'u8])
  code.emit(cast[array[4, uint8]](rel))

proc emit_jne_rel32*(code: var seq[uint8], rel: int32) =
  code.emit([0x0F'u8, 0x85'u8])
  code.emit(cast[array[4, uint8]](rel))
proc emit_test_al_al*(code: var seq[uint8]) =
  code.emit([0x84'u8, 0xC0'u8])

proc emit_jmp_rax*(code: var seq[uint8]) =
  ## jmp rax
  code.emit([0xFF'u8, 0xE0'u8])
