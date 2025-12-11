{.used.}

## Minimal AArch64 emitters for the baseline JIT.

proc emit*(code: var seq[uint32], word: uint32) {.inline.} =
  code.add(word)

proc emit_movz*(code: var seq[uint32], reg: uint8, imm16: uint16, shift: uint8 = 0) =
  ## movz Xd, imm16, lsl #shift
  ## shift is expressed in bits and must be a multiple of 16 (0, 16, 32, 48).
  let hw = (shift div 16) and 0x3
  code.emit(0xD2800000'u32 or (uint32(hw) shl 21) or (uint32(imm16) shl 5) or uint32(reg and 0x1F))

proc emit_movk*(code: var seq[uint32], reg: uint8, imm16: uint16, shift: uint8 = 0) =
  ## movk Xd, imm16, lsl #shift
  let hw = (shift div 16) and 0x3
  code.emit(0xF2800000'u32 or (uint32(hw) shl 21) or (uint32(imm16) shl 5) or uint32(reg and 0x1F))

proc emit_mov_reg_imm64*(code: var seq[uint32], reg: uint8, imm: uint64) =
  ## Materialise a 64-bit immediate into Xreg using MOVZ+MOVK slices.
  code.emit_movz(reg, uint16(imm and 0xFFFF), 0)
  code.emit_movk(reg, uint16((imm shr 16) and 0xFFFF), 16)
  code.emit_movk(reg, uint16((imm shr 32) and 0xFFFF), 32)
  code.emit_movk(reg, uint16((imm shr 48) and 0xFFFF), 48)

proc emit_blr_reg*(code: var seq[uint32], reg: uint8) =
  ## blr Xreg
  code.emit(0xD63F0000'u32 or (uint32(reg and 0x1F) shl 5))

proc emit_ret*(code: var seq[uint32]) =
  ## ret
  code.emit(0xD65F03C0'u32)

proc emit_sub_sp_imm*(code: var seq[uint32], imm: uint16) =
  ## sub sp, sp, #imm (64-bit, shift=0)
  code.emit(0xD1000000'u32 or (uint32(imm and 0x0FFF) shl 10) or (31'u32 shl 5) or 31'u32)

proc emit_add_sp_imm*(code: var seq[uint32], imm: uint16) =
  ## add sp, sp, #imm (64-bit, shift=0)
  code.emit(0x91000000'u32 or (uint32(imm and 0x0FFF) shl 10) or (31'u32 shl 5) or 31'u32)

proc emit_str_sp_imm*(code: var seq[uint32], reg: uint8, offset_bytes: uint16) =
  ## str Xreg, [sp, #offset]
  let imm = (offset_bytes div 8) and 0x0FFF
  code.emit(0xF9000000'u32 or (uint32(imm) shl 10) or (31'u32 shl 5) or uint32(reg and 0x1F))

proc emit_ldr_sp_imm*(code: var seq[uint32], reg: uint8, offset_bytes: uint16) =
  ## ldr Xreg, [sp, #offset]
  let imm = (offset_bytes div 8) and 0x0FFF
  code.emit(0xF9400000'u32 or (uint32(imm) shl 10) or (31'u32 shl 5) or uint32(reg and 0x1F))

proc emit_b_rel26*(code: var seq[uint32], imm: int) =
  ## Unconditional branch with signed 26-bit immediate (instruction words).
  code.emit(0x14000000'u32 or (uint32(imm) and 0x03FFFFFF'u32))

proc emit_cbnz_w_rel19*(code: var seq[uint32], reg: uint8, imm: int) =
  ## cbnz Wreg, label (signed 19-bit immediate in instruction words).
  code.emit(0x35000000'u32 or ((uint32(imm) and 0x7FFFF'u32) shl 5) or uint32(reg and 0x1F))

# 16-bit load/store
proc emit_ldrh_reg_imm*(code: var seq[uint32], rt, rn: uint8, imm_bytes: uint16) =
  ## ldrh Wt, [Xn, #imm]
  let imm = (imm_bytes div 2) and 0x0FFF
  code.emit(0x79400000'u32 or (uint32(imm) shl 10) or (uint32(rn and 0x1F) shl 5) or uint32(rt and 0x1F))

proc emit_strh_reg_imm*(code: var seq[uint32], rt, rn: uint8, imm_bytes: uint16) =
  ## strh Wt, [Xn, #imm]
  let imm = (imm_bytes div 2) and 0x0FFF
  code.emit(0x79000000'u32 or (uint32(imm) shl 10) or (uint32(rn and 0x1F) shl 5) or uint32(rt and 0x1F))

# 64-bit unsigned offset loads/stores (imm is in bytes, must be multiple of 8)
proc emit_ldr_reg_imm*(code: var seq[uint32], rt, rn: uint8, imm_bytes: uint16) =
  ## ldr Xt, [Xn, #imm]
  let imm = (imm_bytes div 8) and 0x0FFF
  code.emit(0xF9400000'u32 or (uint32(imm) shl 10) or (uint32(rn and 0x1F) shl 5) or uint32(rt and 0x1F))

proc emit_str_reg_imm*(code: var seq[uint32], rt, rn: uint8, imm_bytes: uint16) =
  ## str Xt, [Xn, #imm]
  let imm = (imm_bytes div 8) and 0x0FFF
  code.emit(0xF9000000'u32 or (uint32(imm) shl 10) or (uint32(rn and 0x1F) shl 5) or uint32(rt and 0x1F))

# 64-bit arithmetic (immediate)
proc emit_add_reg_imm*(code: var seq[uint32], rd, rn: uint8, imm12: uint16) =
  ## add Xd, Xn, #imm12
  let imm = imm12 and 0x0FFF
  code.emit(0x91000000'u32 or (uint32(imm) shl 10) or (uint32(rn and 0x1F) shl 5) or uint32(rd and 0x1F))

proc emit_sub_reg_imm*(code: var seq[uint32], rd, rn: uint8, imm12: uint16) =
  ## sub Xd, Xn, #imm12
  let imm = imm12 and 0x0FFF
  code.emit(0xD1000000'u32 or (uint32(imm) shl 10) or (uint32(rn and 0x1F) shl 5) or uint32(rd and 0x1F))

# 64-bit arithmetic (register)
proc emit_add_reg_reg*(code: var seq[uint32], rd, rn, rm: uint8) =
  ## add Xd, Xn, Xm
  code.emit(0x8B000000'u32 or (uint32(rm and 0x1F) shl 16) or (uint32(rn and 0x1F) shl 5) or uint32(rd and 0x1F))

proc emit_sub_reg_reg*(code: var seq[uint32], rd, rn, rm: uint8) =
  ## sub Xd, Xn, Xm
  code.emit(0xCB000000'u32 or (uint32(rm and 0x1F) shl 16) or (uint32(rn and 0x1F) shl 5) or uint32(rd and 0x1F))

proc emit_add_reg_reg_lsl*(code: var seq[uint32], rd, rn, rm: uint8, shift: uint8) =
  ## add Xd, Xn, Xm, lsl #shift (shift encoded in imm6 at bits 10-15)
  let sh = (shift and 0x3F).uint32
  code.emit(0x8B000000'u32 or (uint32(rm and 0x1F) shl 16) or (sh shl 10) or (uint32(rn and 0x1F) shl 5) or uint32(rd and 0x1F))

# Logical ops
proc emit_and_reg_reg*(code: var seq[uint32], rd, rn, rm: uint8) =
  ## and Xd, Xn, Xm
  code.emit(0x8A000000'u32 or (uint32(rm and 0x1F) shl 16) or (uint32(rn and 0x1F) shl 5) or uint32(rd and 0x1F))

proc emit_orr_reg_reg*(code: var seq[uint32], rd, rn, rm: uint8) =
  ## orr Xd, Xn, Xm
  code.emit(0xAA000000'u32 or (uint32(rm and 0x1F) shl 16) or (uint32(rn and 0x1F) shl 5) or uint32(rd and 0x1F))

# Compare / branch on zero (64-bit)
proc emit_cmp_reg_reg*(code: var seq[uint32], rn, rm: uint8) =
  ## cmp Xn, Xm  (alias for subs xzr, xn, xm)
  code.emit(0xEB000000'u32 or (uint32(rm and 0x1F) shl 16) or (uint32(rn and 0x1F) shl 5) or 0x1Fu32)

proc emit_cbz_x_rel19*(code: var seq[uint32], rt: uint8, imm: int) =
  ## cbz Xt, label (signed 19-bit immediate in instruction words)
  code.emit(0xB4000000'u32 or ((uint32(imm) and 0x7FFFF'u32) shl 5) or uint32(rt and 0x1F))

proc emit_cbnz_x_rel19*(code: var seq[uint32], rt: uint8, imm: int) =
  ## cbnz Xt, label (signed 19-bit immediate in instruction words)
  code.emit(0xB5000000'u32 or ((uint32(imm) and 0x7FFFF'u32) shl 5) or uint32(rt and 0x1F))

proc emit_b_cond_rel19*(code: var seq[uint32], cond: uint8, imm: int) =
  ## b.cond label (signed 19-bit immediate in instruction words), cond is low 4 bits.
  code.emit(0x54000000'u32 or ((uint32(imm) and 0x7FFFF'u32) shl 5) or (uint32(cond and 0xF)))
