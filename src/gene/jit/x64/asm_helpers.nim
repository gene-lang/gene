import tables

import ../../types
import ./encoders

type
  AsmBuffer* = object
    code*: seq[uint8]
    labels*: Table[int, int]      # label id -> offset
    patches*: seq[tuple[offset: int, target: int, kind: string]]

proc init_asm*(): AsmBuffer =
  AsmBuffer(code: @[], labels: initTable[int,int](), patches: @[])

proc emit_jmp_abs*(buf: var AsmBuffer, target: pointer) =
  ## Jump to an absolute address via RAX (movabs; jmp rax).
  buf.code.emit_mov_rax_imm64(cast[uint64](target))
  buf.code.emit_jmp_rax()

proc mark_label*(buf: var AsmBuffer, label_id: int) =
  buf.labels[label_id] = buf.code.len

proc add_patch*(buf: var AsmBuffer, target_label: int, kind: string) =
  ## Record a rel32 patch point.
  buf.patches.add((buf.code.len, target_label, kind))
  buf.code.emit([0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]) # placeholder

proc patch_labels*(buf: var AsmBuffer) =
  for p in buf.patches:
    if not buf.labels.hasKey(p.target):
      raise newException(types.Exception, "Undefined JIT label " & $p.target)
    let target_off = buf.labels[p.target]
    let rel = target_off - (p.offset + 4)
    let bytes = cast[array[4,uint8]](rel.int32)
    for i in 0..3:
      buf.code[p.offset + i] = bytes[i]
