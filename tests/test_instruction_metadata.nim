import unittest, strutils

import ../src/gene/types except Exception

suite "Instruction metadata":
  test "all instruction kinds have metadata":
    for kind in InstructionKind:
      let metadata = instruction_metadata(kind)
      check metadata.family.len > 0
      check metadata.stack.note.len >= 0

  test "metadata gaps are explicit":
    let gaps = metadata_gap_kinds()
    check gaps.len > 0
    for kind in gaps:
      check not instruction_metadata(kind).checked

  test "debug formatter includes opcode and operands":
    let inst = Instruction(kind: IkPushValue, arg0: 42.to_value())
    let formatted = format_instruction_debug(inst)
    check formatted.contains("PushValue")
    check formatted.contains("42")

  test "fixed stack metadata exposes minimum pops":
    let pop_effect = instruction_metadata(IkPop).stack
    check pop_effect.kind == SekFixed
    check pop_effect.min_pops == 1
