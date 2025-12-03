# Utility functions for VM operations

import ../types/type_defs
import ../types/value_core

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

#################### JIT Helpers ####################

proc jit_stack_push_value*(vm: VirtualMachine, value: Value) {.exportc, cdecl.} =
  ## Push a value onto the current frame stack.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT push requires an active frame")
  if idx_ptr[] >= vm.frame.stack.len.uint16:
    raise new_exception(type_defs.Exception, "JIT stack overflow")
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  stack_arr[idx_ptr[]] = value
  idx_ptr[] = idx_ptr[] + 1

proc jit_stack_pop_value*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Pop and return the top value from the current frame stack.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT pop requires an active frame")
  if idx_ptr[] == 0:
    raise new_exception(type_defs.Exception, "JIT pop on empty stack")
  idx_ptr[] = idx_ptr[] - 1
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  result = stack_arr[idx_ptr[]]
  stack_arr[idx_ptr[]] = NIL

proc jit_stack_peek_value*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Return the current top value without removing it.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT peek requires an active frame")
  if idx_ptr[] == 0:
    raise new_exception(type_defs.Exception, "JIT peek on empty stack")
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  stack_arr[idx_ptr[] - 1]

proc jit_stack_dup*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Duplicate the top stack value.
  let v = vm.jit_stack_peek_value()
  vm.jit_stack_push_value(v)

proc jit_stack_swap*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Swap the top two stack values.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT swap requires an active frame")
  if idx_ptr[] < 2:
    raise new_exception(type_defs.Exception, "JIT swap requires at least two values")
  let top_idx = idx_ptr[] - 1
  let second_idx = idx_ptr[] - 2
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  let tmp = stack_arr[top_idx]
  stack_arr[top_idx] = stack_arr[second_idx]
  stack_arr[second_idx] = tmp

proc jit_stack_pop_discard*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Pop and drop the top stack value.
  discard vm.jit_stack_pop_value()

proc jit_var_resolve_push*(vm: VirtualMachine, slot: int32): Value {.exportc, cdecl.} =
  ## Resolve a local variable and push it onto the stack.
  if vm.frame.is_nil or vm.frame.scope.isNil:
    raise new_exception(type_defs.Exception, "JIT VarResolve requires an active scope")
  let index = slot.int
  if index < 0 or index >= vm.frame.scope.members.len:
    raise new_exception(type_defs.Exception, "JIT VarResolve out of bounds")
  let value = vm.frame.scope.members[index]
  vm.jit_stack_push_value(value)
  result = value

proc jit_var_assign_top*(vm: VirtualMachine, slot: int32) {.exportc, cdecl.} =
  ## Assign the current top-of-stack value into a scope slot.
  if vm.frame.is_nil or vm.frame.scope.isNil:
    raise new_exception(type_defs.Exception, "JIT VarAssign requires an active scope")
  let index = slot.int
  if index < 0 or index >= vm.frame.scope.members.len:
    raise new_exception(type_defs.Exception, "JIT VarAssign out of bounds")
  vm.frame.scope.members[index] = vm.jit_stack_peek_value()

proc jit_add_ints*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Pop two ints, add them, and push the result.
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT add supports integers only")
  let sum = (lhs.int64 + rhs.int64).to_value()
  vm.jit_stack_push_value(sum)
  sum

proc jit_compare_lt*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT < supports integers only")
  let res = (lhs.int64 < rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_le*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT <= supports integers only")
  let res = (lhs.int64 <= rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_gt*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT > supports integers only")
  let res = (lhs.int64 > rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_ge*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT >= supports integers only")
  let res = (lhs.int64 >= rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_eq*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT == supports integers only")
  let res = (lhs.int64 == rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_pop_is_false*(vm: VirtualMachine): bool {.exportc, cdecl.} =
  ## Pop the top value and report whether it is falsey.
  let v = vm.jit_stack_pop_value()
  (v == FALSE) or (v == NIL)
