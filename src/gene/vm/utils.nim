# Utility functions for VM operations

import ../types/type_defs

proc string_to_bytes*(s: string): seq[byte] {.inline.} =
  ## Convert a string to a byte sequence
  result = newSeq[byte](s.len)
  var i = 0
  for c in s:
    result[i] = byte(ord(c))
    inc i

proc bytes_to_string*(b: seq[byte]): string {.inline.} =
  ## Convert a byte sequence to a string
  result = newString(b.len)
  var i = 0
  for v in b:
    result[i] = char(v)
    inc i

proc jit_current_stack_ptr*(vm: VirtualMachine): ptr Value {.exportc, cdecl.} =
  ## Return pointer to the current frame's stack base (for JIT use).
  if vm.frame == nil:
    return nil
  addr vm.frame.stack[0]

proc jit_current_stack_index_ptr*(vm: VirtualMachine): ptr uint16 {.exportc, cdecl.} =
  ## Return pointer to the current frame's stack_index (for JIT use).
  if vm.frame == nil:
    return nil
  addr vm.frame.stack_index
