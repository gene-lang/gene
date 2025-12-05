import tables

import ../../types
import ./encoders

type
  AsmBuffer* = object
    ## Holds encoded instructions plus labels/patches for later fixups.
    code*: seq[uint32]
    labels*: Table[int, int]      # label id -> instruction index
    patches*: seq[tuple[offset: int, target: int, kind: string]]

proc init_asm*(): AsmBuffer =
  AsmBuffer(code: @[], labels: initTable[int,int](), patches: @[])

proc mark_label*(buf: var AsmBuffer, label_id: int) =
  buf.labels[label_id] = buf.code.len

proc emit_mov_reg_imm64*(buf: var AsmBuffer, reg: uint8, imm: uint64) =
  buf.code.emit_mov_reg_imm64(reg, imm)

proc emit_helper_call*(buf: var AsmBuffer, target: pointer) =
  ## Load an absolute address into X16 and branch with link.
  buf.emit_mov_reg_imm64(16, cast[uint64](target))
  buf.code.emit_blr_reg(16)

proc add_patch*(buf: var AsmBuffer, target_label: int, kind: string) =
  ## Record a branch that needs its offset patched later.
  buf.patches.add((buf.code.len, target_label, kind))
  buf.code.add(0'u32) # placeholder

proc patch_labels*(buf: var AsmBuffer) =
  for p in buf.patches:
    if not buf.labels.hasKey(p.target):
      raise newException(types.Exception, "Undefined JIT label " & $p.target)
    let target_idx = buf.labels[p.target]
    let branch_idx = p.offset
    let diff = target_idx - (branch_idx + 1) # instruction words
    case p.kind
    of "b":
      if diff < -33554432 or diff > 33554431:
        raise newException(types.Exception, "Branch target out of range")
      buf.code[p.offset] = 0x14000000'u32 or (uint32(diff) and 0x03FFFFFF'u32)
    of "cbnz":
      if diff < -262144 or diff > 262143:
        raise newException(types.Exception, "Conditional branch target out of range")
      buf.code[p.offset] = 0x35000000'u32 or ((uint32(diff) and 0x7FFFF'u32) shl 5) or 0'u32
    else:
      raise newException(types.Exception, "Unknown patch kind " & p.kind)

proc emit_ret*(buf: var AsmBuffer) =
  buf.code.emit_ret()
